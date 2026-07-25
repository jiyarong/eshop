module Ec
  class InventorySnapshot
    SNAPSHOT_TYPE = "inventory".freeze
    PLATFORMS = %w[wb ozon].freeze
    PLATFORM_STOCK_TYPES = %w[fbo fbw].freeze

    def self.snapshot_type
      SNAPSHOT_TYPE
    end

    def self.capture(snapshot_date:)
      skus = Ec::Sku.find_each.to_a
      metrics_by_sku = Ec::InventoryTurnoverMetricsQuery.new(
        sku_codes: skus.map(&:sku_code),
        date_to: snapshot_date,
        time_zone: snapshot_time_zone
      ).call
      levels_by_sku = historical_levels(snapshot_date).group_by(&:sku_code)

      skus.map do |sku|
        levels = levels_by_sku.fetch(sku.sku_code, [])
        metrics = metrics_by_sku.fetch(sku.sku_code, {})
        raw_inventory_row = historical_inventory_row(sku, levels, metrics)
        inventory_row = Ec::InventoryReportRowMetricsBuilder.call(
          raw_inventory_row,
          metrics: metrics
        )
        content = {
          overview: inventory_row.merge(
            platform_totals: platform_totals(levels),
            out_of_stock: inventory_row[:platform_stock].to_i <= 0
          )
        }
        content[:distribution] = { levels: levels.map { |level| distribution_level(level) } } if levels.any?

        {
          sku_id: sku.id,
          content: content
        }
      end
    end

    def self.historical_levels(snapshot_date)
      cutoff = snapshot_time_zone.local(snapshot_date.year, snapshot_date.month, snapshot_date.day).end_of_day

      Ec::SkuInventoryLevel
        .where(synced_at: ..cutoff)
        .select(<<~SQL.squish)
          DISTINCT ON (sku_code, platform, account_id, fulfillment_type)
          ec_sku_inventory_levels.*
        SQL
        .order(:sku_code, :platform, :account_id, :fulfillment_type, synced_at: :desc, id: :desc)
    end
    private_class_method :historical_levels

    def self.historical_inventory_row(sku, levels, metrics)
      platform_inbound_stock = levels
        .select { |level| level.fulfillment_type == "inbound" }
        .sum(&:quantity)
      platform_stock = levels
        .select { |level| level.fulfillment_type.in?(PLATFORM_STOCK_TYPES) }
        .sum(&:quantity)
      book_stock = metrics[:book_stock].to_i
      cost = sku.cost

      {
        sku_code: sku.sku_code,
        product_name: sku.product_name,
        product_name_ru: sku.product_name_ru,
        marketing_grade: sku.current_marketing_state&.grade,
        marketing_stage: sku.current_marketing_state&.stage,
        incoming_quantity: metrics[:procurement_stock].to_i,
        book_stock: book_stock,
        platform_inbound_stock: platform_inbound_stock,
        platform_stock: platform_stock,
        available_stock: book_stock - platform_stock - platform_inbound_stock,
        pkg_length_cm: cost&.pkg_length_cm,
        pkg_width_cm: cost&.pkg_width_cm,
        pkg_height_cm: cost&.pkg_height_cm,
        unit_volume_l: cost&.pkg_volume_l
      }
    end
    private_class_method :historical_inventory_row

    def self.snapshot_time_zone
      @snapshot_time_zone ||= Time.find_zone!(Ec::Snapshot::TIME_ZONE)
    end
    private_class_method :snapshot_time_zone

    def self.platform_totals(levels)
      platforms = (PLATFORMS + levels.map(&:platform)).uniq

      platforms.index_with do |platform|
        platform_levels = levels.select { |level| level.platform == platform }
        quantities = Ec::SkuInventoryLevel::FULFILLMENT_TYPES.index_with do |fulfillment_type|
          platform_levels
            .select { |level| level.fulfillment_type == fulfillment_type }
            .sum(&:quantity)
        end
        platform_stock = PLATFORM_STOCK_TYPES.sum { |type| quantities[type].to_i }

        {
          platform_stock: platform_stock,
          quantity_by_fulfillment: quantities,
          out_of_stock: platform_stock <= 0
        }
      end
    end
    private_class_method :platform_totals

    def self.distribution_level(level)
      {
        platform: level.platform,
        store_id: level.store_id,
        store_name: level.store_name,
        account_id: level.account_id,
        fulfillment_type: level.fulfillment_type,
        quantity: level.quantity,
        synced_at: level.synced_at,
        metadata: level.metadata,
        warehouse_breakdown: level.warehouse_breakdown
      }
    end
    private_class_method :distribution_level
  end
end
