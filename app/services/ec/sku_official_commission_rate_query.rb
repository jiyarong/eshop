module Ec
  class SkuOfficialCommissionRateQuery
    PLATFORMS = %w[wb ozon].freeze

    SOURCE_FIELD_BY_PLATFORM_AND_MODE = {
      [ "wb", "fbs" ] => "kgvp_marketplace",
      [ "wb", "fbo" ] => "paid_storage_kgvp",
      [ "ozon", "fbo" ] => "sales_percent_fbo",
      [ "ozon", "fbs" ] => "sales_percent_fbs"
    }.freeze

    def self.run(sku:, platform:, delivery_mode:)
      new(sku:, platform:, delivery_mode:).run
    end

    def initialize(sku:, platform:, delivery_mode:, wb_resolver: RawWb::CommissionTariffResolver.new,
      ozon_resolver: RawOzon::CommissionTariffResolver.new)
      @sku = sku
      @platform = platform.to_s.downcase
      @delivery_mode = delivery_mode.to_s.downcase
      @wb_resolver = wb_resolver
      @ozon_resolver = ozon_resolver
    end

    def run
      raise ArgumentError, "unsupported platform" unless PLATFORMS.include?(@platform)
      raise ArgumentError, "unsupported delivery mode" unless source_field

      bindings = @sku.sku_products.active
        .includes(:store)
        .joins(:store)
        .merge(Ec::Store.active)
        .where(ec_sku_products: { platform: @platform })
        .order(:id)
        .to_a
      resolved = []
      errors = []

      bindings.each do |binding|
        begin
          resolved << resolve_binding(binding)
        rescue RawWb::CommissionTariffResolver::ResolutionError,
          RawOzon::CommissionTariffResolver::ResolutionError => error
          errors << error.code.to_s
        rescue ArgumentError
          errors << "invalid_product_id"
        end
      end

      {
        platform: @platform,
        delivery_mode: @delivery_mode,
        binding_count: bindings.size,
        resolved_count: resolved.size,
        unresolved_count: bindings.size - resolved.size,
        rates: grouped_rates(resolved),
        source: source_metadata(resolved),
        errors: errors.tally
      }
    end

    private

    def resolve_binding(binding)
      @platform == "wb" ? resolve_wb_binding(binding) : resolve_ozon_binding(binding)
    end

    def resolve_wb_binding(binding)
      account_id = binding.store.wb_raw_account_id
      raise RawWb::CommissionTariffResolver::ResolutionError.new(:missing_subject_tariff) if account_id.blank?

      product = RawWb::Product.find_by!(account_id:, nm_id: Integer(binding.product_id, 10))
      {
        rate: @wb_resolver.rate_for_wb_product(product:, delivery_mode: @delivery_mode),
        binding: binding,
        synced_at: RawWb::CommissionTariffSnapshot.current&.fetched_at
      }
    rescue ActiveRecord::RecordNotFound
      raise RawWb::CommissionTariffResolver::ResolutionError.new(:missing_subject_tariff)
    end

    def resolve_ozon_binding(binding)
      account_id = binding.store.ozon_raw_account_id
      raise RawOzon::CommissionTariffResolver::ResolutionError.new(:missing_commission_rate) if account_id.blank?

      product_id = Integer(binding.product_id, 10)
      {
        rate: @ozon_resolver.rate_for(
          account_id: account_id,
          ozon_product_id: product_id,
          delivery_mode: @delivery_mode
        ),
        binding: binding,
        synced_at: RawOzon::ProductPrice.where(account_id:, ozon_product_id: product_id).pick(:synced_at)
      }
    end

    def grouped_rates(resolved)
      resolved.group_by { |entry| entry.fetch(:rate) }.map do |rate, entries|
        {
          rate: rate.to_s("F"),
          product_count: entries.size,
          store_count: entries.map { |entry| entry.fetch(:binding).store_id }.uniq.size,
          product_ids: entries.map { |entry| entry.fetch(:binding).product_id }
        }
      end.sort_by { |entry| BigDecimal(entry.fetch(:rate)) }
    end

    def source_metadata(resolved)
      {
        field: source_field,
        synced_at: resolved.filter_map { |entry| entry[:synced_at] }.max&.iso8601
      }
    end

    def source_field
      SOURCE_FIELD_BY_PLATFORM_AND_MODE[[@platform, @delivery_mode]]
    end
  end
end
