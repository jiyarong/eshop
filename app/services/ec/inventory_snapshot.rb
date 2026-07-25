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
      metrics_by_sku = Ec::InventoryVelocityMetricsQuery.new(
        sku_codes: skus.map(&:sku_code),
        date_to: snapshot_date,
        time_zone: Time.find_zone!(Ec::Snapshot::TIME_ZONE)
      ).call

      skus.map do |sku|
        levels = sku.inventory_levels.latest.order(:platform, :store_name, :fulfillment_type).to_a
        raw_inventory_row = Ec::InventoryPageRowQuery.new(sku).call
        inventory_row = Ec::InventoryReportRowMetricsBuilder.call(
          raw_inventory_row,
          metrics: metrics_by_sku.fetch(sku.sku_code, {})
        )

        {
          sku_id: sku.id,
          content: {
            overview: inventory_row.merge(
              platform_totals: platform_totals(levels),
              out_of_stock: inventory_row[:platform_stock].to_i <= 0
            ),
            distribution: {
              levels: levels.map { |level| distribution_level(level) }
            }
          }
        }
      end
    end

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
