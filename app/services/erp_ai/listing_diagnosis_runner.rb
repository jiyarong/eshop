module ErpAI
  class ListingDiagnosisRunner
    AGENT_CODE = "listing-audit".freeze
    RECENT_WEEK_COUNT = 4

    def self.run(suggestion_id:)
      new(suggestion: Ec::AISuggestion.find(suggestion_id)).run
    end

    def initialize(
      suggestion:,
      listing_context: ErpAI::ListingDiagnosisContext,
      sales_funnel_context: ErpAI::V2::SalesFunnelContext,
      runner_factory: ->(agent:, user:) { ErpAI::AgentRunner.new(agent: agent, user: user) },
      today: nil
    )
      @suggestion = suggestion
      @listing_context = listing_context
      @sales_funnel_context = sales_funnel_context
      @runner_factory = runner_factory
      @today = today
    end

    def run
      validate_suggestion!
      return suggestion unless start!

      conversation = runner_factory.call(
        agent: Agent.enabled.find_by!(code: AGENT_CODE),
        user: suggestion.submitted_by
      ).ask(
        question: I18n.t("erp.sku_products.listing_diagnosis.agent_question"),
        module_name: "listing_diagnosis",
        business_object_type: "Ec::SkuProduct",
        business_object_id: sku_product.id,
        time_range: { from: period_from.iso8601, to: period_to.iso8601 },
        data_summary: data_summary
      )
      result = conversation.messages.where(role: "assistant").order(:created_at, :id).last!.content
      suggestion.update!(
        status: :completed,
        conversation: conversation,
        content: result,
        error_message: nil,
        completed_at: Time.current
      )
      suggestion
    rescue StandardError => error
      fail!(error)
      raise
    end

    private

    attr_reader :suggestion, :listing_context, :sales_funnel_context, :runner_factory

    def validate_suggestion!
      return if listing_audit_suggestion?

      raise ArgumentError, "invalid_listing_audit_suggestion"
    end

    def listing_audit_suggestion?
      suggestion.suggestion_type == Ec::AISuggestion::LISTING_AUDIT_TYPE &&
        suggestion.suggestable_type == "Ec::SkuProduct"
    end

    def start!
      suggestion.with_lock do
        return false unless suggestion.pending?

        suggestion.update!(status: :running, started_at: Time.current, error_message: nil)
      end
      true
    end

    def fail!(error)
      return unless listing_audit_suggestion? && suggestion.persisted? && !suggestion.completed?

      suggestion.update!(
        status: :failed,
        error_message: error.message.to_s.presence || error.class.name,
        completed_at: Time.current
      )
    rescue ActiveRecord::RecordNotFound
      nil
    end

    def data_summary
      [
        target_context,
        listing_context.call(sku_code: sku_product.sku_code),
        sales_funnel_summary
      ].join("\n---\n\n")
    end

    def target_context
      <<~MARKDOWN.rstrip
        # 当前诊断目标

        - platform: #{sku_product.platform}
        - store_id: #{sku_product.store_id}
        - store_name: #{sku_product.store.store_name}
        - product_id: #{sku_product.product_id}
        - platform_sku_id: #{sku_product.platform_sku_id.presence || "_未提供_"}
        - sku_code: #{sku_product.sku_code}
      MARKDOWN
    end

    def sales_funnel_summary
      <<~MARKDOWN.rstrip
        # 近期销售漏斗

        数据范围：#{period_from.iso8601} 至 #{period_to.iso8601}（最近 #{RECENT_WEEK_COUNT} 个完整自然周）

        ```json
        #{JSON.pretty_generate(sales_funnel_data)}
        ```
      MARKDOWN
    end

    def sales_funnel_data
      sales_funnel_context.new(
        sku: sku_product.sku,
        period_from: period_from,
        period_to: period_to,
        store_options: [store_option]
      ).call
    end

    def store_option
      {
        ref: "#{sku_product.platform}:#{raw_account_id}",
        platform: sku_product.platform,
        name: sku_product.store.store_name,
        label: sku_product.store.store_name
      }
    end

    def raw_account_id
      if sku_product.platform == "ozon"
        sku_product.store.ozon_raw_account_id
      else
        sku_product.store.wb_raw_account_id
      end
    end

    def period_to
      @period_to ||= effective_today.beginning_of_week(:monday) - 1.day
    end

    def period_from
      @period_from ||= period_to.beginning_of_week(:monday) - (RECENT_WEEK_COUNT - 1).weeks
    end

    def effective_today
      @today || Time.current.in_time_zone(User.profile_time_zone(suggestion.submitted_by.time_zone)).to_date
    end

    def sku_product
      @sku_product ||= suggestion.suggestable
    end
  end
end
