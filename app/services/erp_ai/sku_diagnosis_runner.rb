module ErpAI
  class SkuDiagnosisRunner
    AGENT_CODE = "sku_diagnosis".freeze
    TIME_ZONE = "Asia/Shanghai".freeze
    SUMMARY_MIN_LATEST_EVENT_COUNT = 5
    SUMMARY_MAX_EVENT_AGE = 30.hours
    SUMMARY_CONTEXT_KEYS = %w[base lifecycle sales_funnel inventory].freeze
    SUMMARY_CONTEXT_WEEKS = 4
    ADVICE_EVENT_SCOPE = "advise".freeze
    ADVICE_SYSTEM_PROMPT = <<~PROMPT.strip.freeze
      你是电商运营建议生成器。请基于当前 SKU 近四周各子规则的诊断结果，提炼需要运营执行的具体动作。不要修改、忽略或评价任何已有诊断事件；只通过 create_sku_advise 创建新的建议事件。建议要能直接交给运营执行，使用电商业务人员熟悉的表达，不能编造上下文中没有的数据。
    PROMPT

    class ScopedToolExecutor
      def initialize(user:, date:, sku:, rule: nil, expected_event_type: nil, allowed_tools: [ "save_sku_event" ])
        @sku = sku
        @rule = rule
        @expected_event_type = expected_event_type
        @allowed_tools = allowed_tools
        @executor = ErpAI::ToolExecutor.new(mcp_clients: {}, current_user: user, event_date: date)
      end

      def conversation_id=(conversation_id)
        @executor.conversation_id = conversation_id
      end

      def call(id:, name:, arguments:)
        args = arguments.to_h.stringify_keys
        if !@allowed_tools.include?(name) || args["sku_code"].to_s.upcase != @sku.sku_code
          return { tool_call_id: id, name: name, error: { code: "invalid_scope" } }
        end

        if name == "save_sku_event" && (
          Integer(args["sub_agent_id"], exception: false) != @rule&.id ||
          %w[event_type message].any? { |key| args[key].blank? } ||
          !%w[info warning critical].include?(args["severity"]) ||
          (@expected_event_type.present? && args["event_type"] != @expected_event_type)
        )
          return { tool_call_id: id, name: name, error: { code: "invalid_scope" } }
        end

        if name == "create_sku_advise"
          args.delete("advise")
          args["scope"] = ADVICE_EVENT_SCOPE
        end

        @executor.call(id: id, name: name, arguments: args)
      end
    end

    def self.run(as_of_date: nil, sku_code: nil, rule_ids: nil, summary: false, force: false)
      new(as_of_date: as_of_date, sku_code: sku_code, rule_ids: rule_ids, summary: summary, force: force).run
    end

    def initialize(
      as_of_date:, sku_code: nil, rule_ids: nil, summary: false, force: false, client: DefaultClient.new, user: nil,
      snapshot_fetcher: Ec::SkuContextSnapshotFetcher,
      listing_context: ErpAI::ListingDiagnosisContext,
      product_attributes_context: ErpAI::V3::ProductAttributesContext
    )
      @as_of_date = as_of_date.present? ? as_of_date.to_date : Time.current.in_time_zone(TIME_ZONE).to_date
      @sku_code = sku_code
      @rule_ids = rule_ids&.filter_map { |id| Integer(id, exception: false) }&.uniq
      @summary = summary
      @force = force
      @client = client
      @user = user
      @snapshot_fetcher = snapshot_fetcher
      @listing_context = listing_context
      @product_attributes_context = product_attributes_context
    end

    def run
      agent = Agent.ensure_fixed!(AGENT_CODE)
      return unless agent.enabled?

      user = @user || execution_user
      rules = if rule_ids.nil?
        Ec::SkuDiagnosisRule.enabled_for(as_of_date).order(:id)
      else
        Ec::SkuDiagnosisRule.where(id: rule_ids).order(:id)
      end
      skus = if sku_code.present?
        Ec::Sku.where(sku_code: sku_code).includes(:current_marketing_state).to_a
      else
        batch_candidate_skus
      end
      skus.each do |sku|
        rules.each do |rule|
          next if rule_ids.nil? && !rule.applies_to_sku?(sku)

          run_rule(agent, user, sku, rule)
        end
        run_summary(agent, user, sku) if summary && (force || summary_due?(sku))
      end
    end

    private

    attr_reader :as_of_date, :sku_code, :rule_ids, :summary, :force, :client, :snapshot_fetcher, :listing_context,
      :product_attributes_context

    def batch_candidate_skus
      period_from = as_of_date.beginning_of_week(:monday) - 1.week
      period_to = period_from.end_of_week(:monday)
      report = Ec::WeeklySummaryDeepQuery.run(
        from_date: period_from,
        to_date: period_to,
        sku_codes: [],
        include_comparison: false
      )
      report_sku_codes = Array(report[:rows] || report["rows"]).filter_map do |row|
        (row[:sku] || row["sku"]).to_s.strip.upcase.presence
      end.uniq

      Ec::Sku.where(sku_code: report_sku_codes).includes(:current_marketing_state).order(:sku_code).to_a
    end

    def run_rule(agent, user, sku, rule)
      period_from = as_of_date.beginning_of_week(:monday) - 1.week
      period_to = period_from.end_of_week(:monday)
      snapshot = snapshot_fetcher.fetch(sku.sku_code, snapshot_date: as_of_date)
      context_keys = rule.context_keys
      selected_listing_platforms = listing_platforms(context_keys)
      context_sections = (context_keys - Ec::SkuDiagnosisRule::LISTING_CONTEXT_KEYS).map do |key|
        context_section(key, snapshot)
      end
      if selected_listing_platforms.any?
        context_sections << listing_context_section(sku, selected_listing_platforms)
      end
      period = snapshot.fetch("period")
      data_summary = [
        "SKU：#{snapshot.fetch('sku_code')}",
        "数据周期：#{period.fetch('from')} 至 #{period.fetch('to')}；快照日期：#{period.fetch('as_of')}",
        context_sections.join("\n\n---\n\n")
      ].join("\n\n")
      event_type_instruction = if rule.allowed_event_types.any?
        "event_type 建议优先使用以下值，也可按诊断结论填写其他具体类型：#{rule.allowed_event_types.join(', ')}"
      else
        "event_type 写具体诊断事件类型"
      end
      listing_image_instruction = if selected_listing_platforms.any?
        "每个 Listing product 的图片均按两张一组排列：第一张为主图，第二张为其余产品图合集。"
      end
      question = <<~PROMPT
        当前 SKU：#{sku.sku_code}
        当前子规则 ID：#{rule.id}
        子规则追加提示词：
        #{rule.prompt}
        #{listing_image_instruction}

        请严格基于下方上下文诊断当前 SKU。必须调用 save_sku_event，sub_agent_id 使用 #{rule.id}，#{event_type_instruction}，message 写诊断结果和依据；severity 使用 info、warning 或 critical 之一。不要处理其他 SKU。
      PROMPT
      conversation = ErpAI::AgentRunner.new(
        agent: agent, user: user, client: client,
        tool_executor: ScopedToolExecutor.new(user: user, date: as_of_date, sku: sku, rule: rule),
        tool_names: [ "save_sku_event" ]
      ).ask(
        question: question,
        module_name: "sku_diagnosis",
        business_object_type: "Ec::Sku",
        business_object_id: sku.id.to_s,
        time_range: { from: period_from.iso8601, to: period_to.iso8601 },
        data_summary: data_summary,
        images: selected_listing_platforms.any? ? listing_images(sku, selected_listing_platforms) : []
      )
      saved = conversation.messages.where(role: "tool").any? do |message|
        payload = JSON.parse(message.content)
        result = payload["result"] || {}
        payload["name"] == "save_sku_event" && result["success"] &&
          result["sku_code"] == sku.sku_code && result["sub_agent_id"] == rule.id
      rescue JSON::ParserError
        false
      end
      raise "SKU diagnosis did not save an event" unless saved

      conversation
    rescue StandardError => e
      Rails.logger.error("SKU diagnosis failed for #{sku.sku_code}/#{rule.id}: #{e.class}: #{e.message}")
    end

    def run_summary(agent, user, sku)
      snapshot = snapshot_fetcher.fetch(sku.sku_code, snapshot_date: as_of_date)
      data_summary = summary_data_summary(sku, snapshot)
      question = <<~PROMPT
        当前 SKU：#{sku.sku_code}

        请根据下方 SKU 上下文和近四周子规则诊断结果，输出方便运营执行的建议操作，不要重新做联合诊断，也不要修改任何已有事件。
        1. 只提炼有明确依据、能改善经营结果或降低风险的动作；相同动作合并，按优先级分别创建事件。
        2. 每次调用 create_sku_advise 只创建一条建议事件：event_type 是具体动作的简写，使用中文且少于 10 个汉字，例如“补充库存”“优化主图”“调整售价”；不要写成“风险”“问题”等诊断名词。
        3. severity 使用 info、warning 或 critical，按执行紧迫程度选择。message 必须同时写清诊断依据和具体实施细节，尽量包含涉及的平台、数量/范围、负责人要做什么、观察什么指标和何时复核；只能使用上下文中已有信息。
        4. 工具不需要也不接受 advise；建议内容全部写入 message，系统会把 scope 固定为 advise。不要调用任何 update 工具，不要处理其他 SKU。
        5. 有明确可执行建议时至少创建一条事件；没有足够依据时不要编造动作，可创建一条说明需要补充什么数据后再执行的建议。
      PROMPT
      conversation = Ec::AIDiagnosis.transaction do
        sku.lock!
        reset_advice_events_for_summary!(sku)

        result = ErpAI::AgentRunner.new(
          agent: agent, user: user, client: client,
          tool_executor: ScopedToolExecutor.new(
            user: user, date: as_of_date, sku: sku,
            allowed_tools: [ "create_sku_advise" ]
          ),
          tool_names: [ "create_sku_advise" ],
          system_prompt: ADVICE_SYSTEM_PROMPT
        ).ask(
          question: question,
          module_name: "sku_diagnosis",
          business_object_type: "Ec::Sku",
          business_object_id: sku.id.to_s,
          time_range: { from: as_of_date.beginning_of_week(:monday).iso8601, to: as_of_date.iso8601 },
          data_summary: data_summary
        )
        tool_messages = result.messages.where(role: "tool").to_a
        saved = tool_messages.present? && tool_messages.all? do |message|
          payload = JSON.parse(message.content)
          tool_result = payload["result"] || {}
          payload["name"] == "create_sku_advise" && tool_result["success"] &&
            tool_result["sku_code"] == sku.sku_code && tool_result["scope"] == ADVICE_EVENT_SCOPE
        rescue JSON::ParserError
          false
        end
        raise "SKU operation advice did not create an event" unless saved

        result
      end

      conversation
    rescue StandardError => e
      Rails.logger.error("SKU operation advice failed for #{sku.sku_code}: #{e.class}: #{e.message}")
    end

    def summary_due?(sku)
      latest_events = latest_sub_agent_events_for(sku)
      return false unless latest_events.count > SUMMARY_MIN_LATEST_EVENT_COUNT

      latest_event = latest_events.order(created_at: :desc, id: :desc).first
      latest_event.present? && latest_event.created_at >= SUMMARY_MAX_EVENT_AGE.ago
    end

    def reset_advice_events_for_summary!(sku)
      day_start = Time.find_zone!(TIME_ZONE).local(as_of_date.year, as_of_date.month, as_of_date.day)
      day_end = day_start + 1.day
      diagnosis = Ec::GeneralDiagnosis
        .where(sku_id: sku.id, created_at: day_start...day_end)
        .order(id: :desc)
        .first
      advice_events = Ec::AIDiagnosisEvent
        .joins(:ai_diagnosis)
        .where(
          sub_agent_id: nil,
          scope: ADVICE_EVENT_SCOPE,
          ec_ai_diagnosis: { sku_id: sku.id, type: Ec::GeneralDiagnosis.sti_name }
        )

      advice_events.where.not(ai_diagnosis_id: diagnosis&.id).update_all(is_latest: false)
      advice_events.where(ai_diagnosis_id: diagnosis.id).delete_all if diagnosis
    end

    def summary_data_summary(sku, snapshot)
      period = snapshot.fetch("period")
      context_sections = SUMMARY_CONTEXT_KEYS.map { |key| context_section(key, snapshot) }
      event_lines = summary_events_for(sku).map do |event|
        week = event.created_at.in_time_zone(TIME_ZONE).beginning_of_week(:monday).to_date
        "- week=#{week}; event_id=#{event.id}; sub_agent_rule.name=#{event.sub_agent&.name || '(unknown)'}; severity=#{event.severity}; event_type=#{event.event_type}; status=#{event.status}; message=#{event.message}"
      end
      [
        "SKU：#{snapshot.fetch('sku_code')}",
        "数据周期：#{period.fetch('from')} 至 #{period.fetch('to')}；快照日期：#{period.fetch('as_of')}",
        context_sections.join("\n\n---\n\n"),
        "**近#{SUMMARY_CONTEXT_WEEKS}周各子规则诊断事件（每周最多一条）**\n#{event_lines.presence&.join("\n") || '暂无可用子规则诊断事件。'}"
      ].join("\n\n")
    end

    def summary_events_for(sku)
      from = summary_context_from
      to = summary_context_to
      events = Ec::AIDiagnosisEvent
        .joins(:ai_diagnosis)
        .where(
          created_at: from...to,
          ec_ai_diagnosis: { sku_id: sku.id, type: Ec::GeneralDiagnosis.sti_name }
        )
        .where.not(sub_agent_id: nil)
        .includes(:sub_agent)
        .order(created_at: :desc, id: :desc)

      events.each_with_object({}) do |event, selected|
        week = event.created_at.in_time_zone(TIME_ZONE).beginning_of_week(:monday).to_date
        selected[[ event.sub_agent_id, week ]] ||= event
      end.values.sort_by { |event| [ event.sub_agent_id, event.created_at, event.id ] }
    end

    def summary_context_from
      summary_context_week_start - (SUMMARY_CONTEXT_WEEKS - 1).weeks
    end

    def summary_context_to
      Time.find_zone!(TIME_ZONE).local(as_of_date.year, as_of_date.month, as_of_date.day) + 1.day
    end

    def summary_context_week_start
      @summary_context_week_start ||= Time.find_zone!(TIME_ZONE).local(
        as_of_date.beginning_of_week(:monday).year,
        as_of_date.beginning_of_week(:monday).month,
        as_of_date.beginning_of_week(:monday).day
      )
    end

    def latest_sub_agent_events_for(sku)
      Ec::AIDiagnosisEvent
        .joins(:ai_diagnosis)
        .where(
          is_latest: true,
          ec_ai_diagnosis: { sku_id: sku.id, type: Ec::GeneralDiagnosis.sti_name }
        )
        .where.not(sub_agent_id: nil)
    end

    def context_section(key, snapshot)
      category = snapshot.dig("categories", key) || raise(KeyError, "missing snapshot category: #{key}")
      [
        "**#{category.fetch('name')}**",
        category["description"].presence || Ec::SkuContextSnapshot.context_descriptions.fetch(key.to_sym),
        category.fetch("markdown").strip
      ].filter_map { |value| value.to_s.strip.presence }.join("\n\n")
    end

    def listing_context_section(sku, platforms)
      attributes = product_attributes_context.call(sku: sku, platforms: platforms)
      [
        listing_context.description,
        listing_context.call(sku: sku, product_attributes: attributes, platforms: platforms).strip
      ].filter_map { |value| value.to_s.strip.presence }.join("\n\n")
    end

    def listing_platforms(context_keys)
      platforms_by_key = {
        "ozon_listing_content" => "ozon",
        "wb_listing_content" => "wb"
      }
      context_keys.filter_map { |key| platforms_by_key[key] }
    end

    def listing_images(sku, platforms)
      sku.sku_products.active.where(platform: platforms).ordered.includes(:store).flat_map do |sku_product|
        listing_context.image_attachments(sku_product: sku_product).filter_map do |attachment|
          attachment.file.blob if attachment.file.attached?
        end
      end
    end

    def execution_user
      User.joins(:roles).where(active: true, roles: { code: "super_admin" }).first || raise("No super admin available for SKU diagnosis")
    end
  end
end
