module Ec
  class SkuProfitVersionContext < ApplicationRecord
    include Ec::Auditable

    self.table_name = "ec_sku_profit_version_contexts"

    PLATFORMS = %w[wb ozon].freeze
    DELIVERY_MODES = %w[fbo fbs].freeze
    COMPANY_TYPES = %w[general small].freeze
    INPUT_COLUMNS = %w[
      purchase_price_cny freight_cny customs_misc_cny duty_rate import_vat_rate
      length_cm width_cm height_cm price_rub rf_price_rub exchange_rate_rub_cny
      commission_rate acquiring_rate advertising_rate tax_rate sales_vat_rate
      logistics_coeff return_rate logistics_tax_rate wb_logistics_base_rub wb_logistics_liter_rub
      wb_fixed_return_base_rub wb_logistics_override_cny fbo_delivery_cny storage_cny damage_rate misc_cny
      other_cny outbound_logistics_rub return_logistics_rub warehouse_operation_rub
      cross_docking_cny return_amortization_factor_override ozon_warehouse_rate
      ozon_import_vat_cost_rate advertising_fixed_rub
    ].freeze
    RESULT_COLUMNS = %w[
      revenue_cny goods_cost_cny import_vat_cny duty_cny logistics_cny returns_cny
      storage_cost_cny commission_cny acquiring_cny advertising_cny tax_cny
      other_cost_cny total_cost_cny profit_cny margin calculation_status
      formula_version calculated_at
    ].freeze

    belongs_to :profit_version,
      class_name: "Ec::SkuProfitVersion",
      foreign_key: :sku_profit_version_id,
      inverse_of: :contexts

    delegate :sku, :sku_id, :effective_from, :effective_to, to: :profit_version

    validates :platform, :market, :delivery_mode, presence: true
    validates :platform, inclusion: { in: PLATFORMS }
    validates :delivery_mode, inclusion: { in: DELIVERY_MODES }
    validates :company_type, inclusion: { in: COMPANY_TYPES }, allow_nil: true
    validates :calculation_status, inclusion: { in: %w[pending valid incomplete] }
    validates :platform,
      uniqueness: { scope: %i[sku_profit_version_id market delivery_mode warehouse_region company_type] }
    validate :ozon_delivery_mode_supported

    before_validation :normalize_context

    def calculation_inputs
      attributes.slice(*INPUT_COLUMNS).compact
    end

    def calculation_result
      attributes.slice(*RESULT_COLUMNS)
    end

    def assign_input_values(values)
      assign_attributes(values.to_h.stringify_keys.slice(*INPUT_COLUMNS))
    end

    def apply_calculation_result(result, calculated_at: Time.current)
      assign_attributes(RESULT_COLUMNS.index_with(nil))
      self.formula_version = result[:formula_version]
      self.calculation_status = result[:errors].present? ? "incomplete" : "valid"
      self.calculated_at = calculated_at
      return if result[:errors].present?

      breakdown = result.fetch(:cost_breakdown)
      assign_attributes(
        revenue_cny: result[:revenue_cny],
        goods_cost_cny: breakdown[:goods],
        import_vat_cny: breakdown[:import_vat],
        duty_cny: breakdown[:duty],
        logistics_cny: breakdown[:logistics],
        returns_cny: breakdown[:returns],
        storage_cost_cny: breakdown[:storage],
        commission_cny: breakdown[:commission],
        acquiring_cny: breakdown[:acquiring],
        advertising_cny: breakdown[:advertising],
        tax_cny: breakdown[:tax],
        other_cost_cny: breakdown[:other],
        total_cost_cny: result[:total_cost_cny],
        profit_cny: result[:profit_cny],
        margin: result[:margin]
      )
    end

    private

    def normalize_context
      self.platform = platform.to_s.downcase.presence
      self.market = market.to_s.downcase.presence
      self.delivery_mode = delivery_mode.to_s.downcase.presence
      self.warehouse_region = warehouse_region.to_s.downcase.presence
      self.company_type = company_type.to_s.downcase.presence
      self.company_type ||= "general" if platform == "ozon"
    end

    def ozon_delivery_mode_supported
      errors.add(:delivery_mode, :inclusion) if platform == "ozon" && delivery_mode != "fbo"
    end
  end
end
