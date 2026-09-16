module ErpAI
  class SkuDiagnosisRunner
    AGENT_CODE = "sku_diagnosis".freeze
    TIME_ZONE = "Asia/Shanghai".freeze

    class ScopedToolExecutor
      def initialize(user:, date:, sku:, rule:)
        @sku = sku
        @rule = rule
        @executor = ErpAI::ToolExecutor.new(mcp_clients: {}, current_user: user, event_date: date)
      end

      def conversation_id=(conversation_id)
        @executor.conversation_id = conversation_id
      end

      def call(id:, name:, arguments:)
        args = arguments.to_h.stringify_keys
        if name != "save_sku_event" || args["sku_code"].to_s.upcase != @sku.sku_code ||
            Integer(args["sub_agent_id"], exception: false) != @rule.id ||
            %w[event_type message advise].any? { |key| args[key].blank? } ||
            !%w[info warning critical].include?(args["severity"])
          return { tool_call_id: id, name: name, error: { code: "invalid_scope" } }
        end

        @executor.call(id: id, name: name, arguments: args)
      end
    end

    def self.run(as_of_date: nil, sku_code: nil, rule_ids: nil)
      new(as_of_date: as_of_date, sku_code: sku_code, rule_ids: rule_ids).run
    end

    def initialize(
      as_of_date:, sku_code: nil, rule_ids: nil, client: DefaultClient.new, user: nil,
      snapshot_fetcher: Ec::SkuContextSnapshotFetcher,
      listing_context: ErpAI::ListingDiagnosisContext,
      product_attributes_context: ErpAI::V3::ProductAttributesContext
    )
      @as_of_date = as_of_date.present? ? as_of_date.to_date : Time.current.in_time_zone(TIME_ZONE).to_date
      @sku_code = sku_code
      @rule_ids = rule_ids&.filter_map { |id| Integer(id, exception: false) }&.uniq
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
      skus = Ec::Sku.where(sku_code: sku_code).to_a if sku_code.present?
      skus ||= Ec::Sku.order(:sku_code).to_a
      skus.each { |sku| rules.each { |rule| run_rule(agent, user, sku, rule) } }
    end

    private

    attr_reader :as_of_date, :sku_code, :rule_ids, :client, :snapshot_fetcher, :listing_context,
      :product_attributes_context

    def run_rule(agent, user, sku, rule)
      period_from = as_of_date.beginning_of_week(:monday) - 1.week
      period_to = period_from.end_of_week(:monday)
      snapshot = snapshot_fetcher.fetch(sku.sku_code, snapshot_date: as_of_date)
      context_keys = rule.context_keys
      context_sections = context_keys.map do |key|
        context_section(key, sku, snapshot)
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
      listing_image_instruction = if context_keys.include?("listing_content")
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
        tool_executor: ScopedToolExecutor.new(user: user, date: as_of_date, sku: sku, rule: rule)
      ).ask(
        question: question,
        module_name: "sku_diagnosis",
        business_object_type: "Ec::Sku",
        business_object_id: sku.id.to_s,
        time_range: { from: period_from.iso8601, to: period_to.iso8601 },
        data_summary: data_summary,
        images: context_keys.include?("listing_content") ? listing_images(sku) : []
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

    def context_section(key, sku, snapshot)
      if key == "listing_content"
        "**Listing Content**\n\n#{listing_context.call(sku: sku).strip}"
      elsif key == "product_attributes"
        attributes = product_attributes_context.call(sku: sku)
        "**Product Attributes**\n\n```json\n#{JSON.pretty_generate(attributes)}\n```"
      else
        category = snapshot.dig("categories", key) || raise(KeyError, "missing snapshot category: #{key}")
        "**#{category.fetch('name')}**\n\n#{category.fetch('markdown').strip}"
      end
    end

    def listing_images(sku)
      sku.sku_products.active.ordered.includes(:store).flat_map do |sku_product|
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
