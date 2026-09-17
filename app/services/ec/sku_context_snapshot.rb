module Ec
  class SkuContextSnapshot
    SNAPSHOT_TYPE = "sku_context".freeze
    RETENTION_DAYS = 10
    API_SCHEMA_PATH = Rails.root.join(
      "app/services/erp_ai/v3/skills/fetch-yuanlong-sku-context/references/api-schema.md"
    ).freeze
    CATEGORIES = {
      base: "基础资料",
      inventory: "库存",
      lifecycle: "生命周期",
      profit: "利润",
      sales_funnel: "销售漏斗",
      advertise_per_week: "广告",
      ec_orders_full_period: "订单",
      supply_orders_full_period: "供应订单",
      operation_actions_full_period: "运营操作",
      warehouse_recommendation: "仓储建议",
      search_terms_per_week: "搜索词"
    }.freeze

    def self.snapshot_type
      SNAPSHOT_TYPE
    end

    def self.retention_days
      RETENTION_DAYS
    end

    def self.capture(snapshot_date:)
      new(snapshot_date: snapshot_date).capture
    end

    def self.capture_for(sku:, snapshot_date:)
      new(
        snapshot_date: snapshot_date,
        sku_scope: Ec::Sku.where(id: sku.id)
      ).capture.sole
    end

    def self.context_descriptions
      @context_descriptions ||= File.read(API_SCHEMA_PATH).scan(
        /^## `[^`]+` \/ `([^`]+)`：[^\n]*\n(.*?)(?=^## |\z)/m
      ).to_h.transform_keys(&:to_sym).transform_values(&:strip).freeze
    end

    def initialize(
      snapshot_date:,
      sku_scope: Ec::Sku.all,
      context_builder: ErpAI::V3::SkuFullContext,
      markdown_renderer: ErpAI::V3::ContextMarkdownRenderer
    )
      @snapshot_date = snapshot_date.to_date
      @sku_scope = sku_scope
      @context_builder = context_builder
      @markdown_renderer = markdown_renderer
    end

    def capture
      sku_scope
        .includes(:current_marketing_state, sku_products: :store, master_sku: :skus)
        .find_each
        .map { |sku| snapshot_row(sku) }
    end

    private

    attr_reader :snapshot_date, :sku_scope, :context_builder, :markdown_renderer

    def snapshot_row(sku)
      payload = context_builder.new(
        sku: sku,
        period_from: period_from,
        period_to: period_to,
        today: snapshot_date,
        time_zone: snapshot_time_zone
      ).call
      data = payload.fetch(:data)
      envelope = data.slice(:schema_version, :sku_code, :period)

      {
        sku_id: sku.id,
        content: envelope.merge(
          categories: CATEGORIES.each_with_object({}) do |(section_key, category_name), categories|
            category_payload = { data: envelope.merge(section_key => data.fetch(section_key)) }
            categories[section_key] = {
              name: category_name,
              description: self.class.context_descriptions.fetch(section_key),
              raw_json: category_payload,
              markdown: markdown_renderer.call(category_payload)
            }
          end
        )
      }
    end

    def period_from
      @period_from ||= snapshot_date.beginning_of_week(:monday) - 1.week
    end

    def period_to
      @period_to ||= period_from.end_of_week(:monday)
    end

    def snapshot_time_zone
      @snapshot_time_zone ||= Time.find_zone!(Ec::Snapshot::TIME_ZONE)
    end
  end
end
