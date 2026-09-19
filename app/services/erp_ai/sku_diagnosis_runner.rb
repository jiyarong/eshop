module ErpAI
  class SkuDiagnosisRunner
    AGENT_CODE = "sku_diagnosis".freeze
    TIME_ZONE = "Asia/Shanghai".freeze
    SUMMARY_EVENT_TYPE = "综合风险".freeze
    SUMMARY_CONTEXT_KEYS = %w[base lifecycle sales_funnel inventory].freeze
    JOINT_SYSTEM_PROMPT = <<~PROMPT.strip.freeze
      你正在执行当前 SKU 的最终联合诊断，而不是单个子规则诊断。所有输入的子规则事件都已经基于各自上下文和规则形成了有依据且合理的判断；你的职责是让这些互相独立的判断彼此可见，解释重叠与冲突，并在确有必要时调用事件修正工具。不要因为结论不同就擅自判定任何子规则错误。
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
          %w[event_type message advise].any? { |key| args[key].blank? } ||
          !%w[info warning critical].include?(args["severity"]) ||
          (@expected_event_type.present? && args["event_type"] != @expected_event_type)
        )
          return { tool_call_id: id, name: name, error: { code: "invalid_scope" } }
        end

        if name == "update_sku_diagnosis_event" && Integer(args["event_id"], exception: false).nil?
          return { tool_call_id: id, name: name, error: { code: "invalid_scope" } }
        end

        @executor.call(id: id, name: name, arguments: args)
      end
    end

    def self.run(as_of_date: nil, sku_code: nil, rule_ids: nil, summary: false)
      new(as_of_date: as_of_date, sku_code: sku_code, rule_ids: rule_ids, summary: summary).run
    end

    def initialize(
      as_of_date:, sku_code: nil, rule_ids: nil, summary: false, client: DefaultClient.new, user: nil,
      snapshot_fetcher: Ec::SkuContextSnapshotFetcher,
      listing_context: ErpAI::ListingDiagnosisContext,
      product_attributes_context: ErpAI::V3::ProductAttributesContext
    )
      @as_of_date = as_of_date.present? ? as_of_date.to_date : Time.current.in_time_zone(TIME_ZONE).to_date
      @sku_code = sku_code
      @rule_ids = rule_ids&.filter_map { |id| Integer(id, exception: false) }&.uniq
      @summary = summary
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
        Ec::Sku.where(sku_code: sku_code).to_a
      else
        batch_candidate_skus
      end
      skus.each do |sku|
        rules.each { |rule| run_rule(agent, user, sku, rule) }
        run_summary(agent, user, sku) if summary
      end
    end

    private

    attr_reader :as_of_date, :sku_code, :rule_ids, :summary, :client, :snapshot_fetcher, :listing_context,
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

      Ec::Sku.where(sku_code: report_sku_codes).order(:sku_code).to_a
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

        请严格基于下方上下文诊断当前 SKU。必须调用 save_sku_event，sub_agent_id 使用 #{rule.id}，#{event_type_instruction}，message 写诊断结果和依据，advise 写操作建议；severity 使用 info、warning 或 critical 之一。不要处理其他 SKU。
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

        这是所有子规则诊断完成后的最终联合诊断。请只分析当前 SKU，并严格使用下方 SKU 上下文和子规则最新事件。
        你必须完成以下工作：
        1. 甄别所有 sub_agent_rule 的 is_latest=true 事件，逐条参考其 event_id、severity、event_type、message、advise 和 sub_agent_rule.name。
        2. 每一项子规则诊断都已经基于自己的上下文和规则完成了有依据且合理的判断。不要因为结论不同就判定某个子规则错误；冲突或重叠通常来自分析视角、证据范围或时间窗口不同。
        3. 识别不同子规则之间 event_type 相同的重复事件，并判断它们是同一问题的重复证据还是独立问题；保留各自合理依据。
        4. 识别 event_type、severity 或结论互相冲突的事件，解释冲突来源、各自依据和需要人工确认的地方；不要强行消除不确定性。
        5. 综合基础资料、生命周期、销售漏斗和库存，给出当前 SKU 的总体判断和按优先级排序的最终建议。

        只有确有必要时才调用 update_sku_diagnosis_event：必须使用上下文中给出的 event_id，只能修改当前 SKU 的子规则事件。severity 只有在联合判断确实需要重新标定优先级时才修改；advise 只有在能显著补充或纠正行动建议时才修改，传入的新 advise 必须以“AI：”开头；只有事件确实是重复、过时或不再需要跟进时才将 status 改为 ignored。不要为了统一格式修改每个事件，也不要因为冲突本身就忽略任何合理事件。未修改的字段必须保留原值。
        如调用了 update_sku_diagnosis_event，必须先完成必要修正，再基于修正后的事件状态、severity 和 advise 生成最终总结。
        最后必须调用 save_sku_event 保存最终结果：sku_code 使用 #{sku.sku_code}，sub_agent_id 必须传 null（不要填写任何子规则 ID），event_type 固定为“#{SUMMARY_EVENT_TYPE}”。最终联合诊断的 severity 必须按总体结论选择：需要立即执行操作时使用 critical，需要关注或跟进时使用 warning，确认无风险时使用 info；不能仅因为存在事件就使用 critical。
        message 必须包含：总体结论、重复事件识别、冲突事件识别、各项结论为何仍合理、关键证据和数据不足；advise 必须包含：按优先级排序的具体行动、验证指标/时限以及无冲突时的保持项。不要处理其他 SKU。
      PROMPT
      conversation = ErpAI::AgentRunner.new(
        agent: agent, user: user, client: client,
        tool_executor: ScopedToolExecutor.new(
          user: user, date: as_of_date, sku: sku, expected_event_type: SUMMARY_EVENT_TYPE,
          allowed_tools: [ "save_sku_event", "update_sku_diagnosis_event" ]
        ),
        tool_names: [ "save_sku_event", "update_sku_diagnosis_event" ],
        system_prompt: JOINT_SYSTEM_PROMPT
      ).ask(
        question: question,
        module_name: "sku_diagnosis",
        business_object_type: "Ec::Sku",
        business_object_id: sku.id.to_s,
        time_range: { from: as_of_date.beginning_of_week(:monday).iso8601, to: as_of_date.iso8601 },
        data_summary: data_summary
      )
      saved = conversation.messages.where(role: "tool").any? do |message|
        payload = JSON.parse(message.content)
        result = payload["result"] || {}
        payload["name"] == "save_sku_event" && result["success"] &&
          result["sku_code"] == sku.sku_code && result["sub_agent_id"].nil? &&
          result["event_type"] == SUMMARY_EVENT_TYPE
      rescue JSON::ParserError
        false
      end
      raise "SKU joint diagnosis did not save an event" unless saved

      conversation
    rescue StandardError => e
      Rails.logger.error("SKU joint diagnosis failed for #{sku.sku_code}: #{e.class}: #{e.message}")
    end

    def summary_data_summary(sku, snapshot)
      period = snapshot.fetch("period")
      context_sections = SUMMARY_CONTEXT_KEYS.map { |key| context_section(key, snapshot) }
      latest_events = Ec::AIDiagnosisEvent
        .joins(:ai_diagnosis)
        .includes(:sub_agent)
        .where(
          is_latest: true,
          ec_ai_diagnosis: { sku_id: sku.id, type: Ec::GeneralDiagnosis.sti_name }
        )
        .where.not(sub_agent_id: nil)
        .order(:sub_agent_id, :id)
      event_lines = latest_events.map do |event|
        "- event_id=#{event.id}; sub_agent_rule.name=#{event.sub_agent&.name || '(unknown)'}; severity=#{event.severity}; event_type=#{event.event_type}; status=#{event.status}; message=#{event.message}; advise=#{event.advise}"
      end
      [
        "SKU：#{snapshot.fetch('sku_code')}",
        "数据周期：#{period.fetch('from')} 至 #{period.fetch('to')}；快照日期：#{period.fetch('as_of')}",
        context_sections.join("\n\n---\n\n"),
        "**所有 sub_agent_rule 的 is_latest=true 事件**\n#{event_lines.presence&.join("\n") || '暂无可用子规则最新事件。'}"
      ].join("\n\n")
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
