module RawWb
  class WarehouseNameResolver
    Result = Data.define(:warehouse_id, :warehouse_name, :region_name, :match_type, :confidence)

    def self.resolve(account_id:, warehouse_name:, on: Date.current)
      new(account_id: account_id, warehouse_name: warehouse_name, on: on).resolve
    end

    def initialize(account_id:, warehouse_name:, on:)
      @account_id = account_id
      @warehouse_name = warehouse_name.to_s.strip
      @on = on.to_date
    end

    def resolve
      return if warehouse_name.blank?

      mapping_result(account_mapping, :account_alias) ||
        mapping_result(global_mapping, :global_alias) ||
        region_result(account_region, :current_name) ||
        unique_cross_account_result
    end

    private

    attr_reader :account_id, :warehouse_name, :on

    def normalized_name
      @normalized_name ||= RawWb::WarehouseRegion.normalize_warehouse_name(warehouse_name)
    end

    def mappings
      RawWb::WarehouseNameMapping.verified
        .effective_on(on)
        .where(normalized_historical_name: normalized_name)
    end

    def account_mapping
      mappings.find_by(account_id: account_id)
    end

    def global_mapping
      mappings.find_by(account_id: nil)
    end

    def account_region
      RawWb::WarehouseRegion.find_by(
        account_id: account_id,
        normalized_warehouse_name: normalized_name
      )
    end

    def unique_cross_account_result
      regions = RawWb::WarehouseRegion
        .where(normalized_warehouse_name: normalized_name)
        .select(:warehouse_id, :warehouse_name, :region_name)
        .distinct
        .to_a
      return unless regions.one?

      region_result(regions.first, :cross_account_name)
    end

    def mapping_result(mapping, match_type)
      return unless mapping

      Result.new(
        warehouse_id: mapping.warehouse_id,
        warehouse_name: mapping.canonical_name,
        region_name: mapping.region_name,
        match_type: match_type,
        confidence: mapping.confidence.to_d
      )
    end

    def region_result(region, match_type)
      return unless region

      Result.new(
        warehouse_id: region.warehouse_id,
        warehouse_name: region.warehouse_name,
        region_name: region.region_name,
        match_type: match_type,
        confidence: 1.to_d
      )
    end
  end
end
