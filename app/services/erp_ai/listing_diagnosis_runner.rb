module ErpAI
  class ListingDiagnosisRunner
    AGENT_CODE = "listing-audit".freeze
    RECENT_WEEK_COUNT = 2

    def self.run(suggestion_id:)
      new(suggestion: Ec::AISuggestion.find(suggestion_id)).run
    end

    def initialize(
      suggestion:,
      listing_context: ErpAI::ListingDiagnosisContext,
      sales_funnel_context: ErpAI::V2::SalesFunnelContext,
      search_terms_query: SearchTermReports::Query,
      runner_factory: ->(agent:, user:) { ErpAI::AgentRunner.new(agent: agent, user: user) },
      today: nil
    )
      @suggestion = suggestion
      @listing_context = listing_context
      @sales_funnel_context = sales_funnel_context
      @search_terms_query = search_terms_query
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
        data_summary: data_summary,
        images: listing_images
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

    attr_reader :suggestion, :listing_context, :sales_funnel_context, :search_terms_query, :runner_factory

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
        listing_context.call(sku_product: sku_product),
        sales_funnel_summary,
        search_terms_summary
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

    def listing_images
      listing_context.image_attachments(sku_product: sku_product).filter_map do |attachment|
        attachment.file.blob if attachment.file.attached?
      end
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
        sku_product: sku_product,
        period_from: period_from,
        period_to: period_to,
        store_options: [store_option]
      ).call
    end

    def search_terms_summary
      <<~MARKDOWN.rstrip
        # 近期搜索关键词

        数据范围：#{period_from.iso8601} 至 #{period_to.iso8601}（最近 #{RECENT_WEEK_COUNT} 个完整自然周）

        字段说明：search_volume 为搜索频次/搜索人数；avg_position 为平均排名（数值越小越靠前）；median_position 为 WB 中位排名；views 为点击或浏览次数。

        ```json
        #{JSON.pretty_generate(search_terms_data)}
        ```
      MARKDOWN
    end

    def search_terms_data
      (period_from..period_to).step(7).map do |week_start|
        week_end = week_start.end_of_week(:monday)
        terms = search_terms_query.new(
          platform: sku_product.platform,
          store: sku_product.store,
          period_from: week_start,
          period_to: week_end,
          sku_codes: [ sku_product.sku_code ]
        ).terms_for(sku_product.sku_code)

        {
          period_from: week_start.iso8601,
          period_to: week_end.iso8601,
          terms: terms.map { |term| term.slice(:keyword, :search_volume, :avg_position, :median_position, :views) }
        }
      end
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
