module Ec
  class SkuCost < ApplicationRecord
    include Ec::Auditable

    self.table_name = 'ec_sku_costs'

    belongs_to :sku, class_name: 'Ec::Sku', foreign_key: :sku_code, primary_key: :sku_code
    has_one :sku_dimension, class_name: "Ec::SkuDimension", foreign_key: :sku_code, primary_key: :sku_code

    scope :effective_as_of, ->(date = Date.current) {
      where("ec_sku_costs.effective_on <= ?", date.to_date)
        .order(effective_on: :desc, id: :desc)
    }

    validates :sku_code, :effective_on, presence: true
    validates :sku_code, uniqueness: { scope: :effective_on }
    before_validation { self.sku_code = sku_code&.upcase }
    before_validation :set_default_effective_on
    after_save :persist_pending_sku_dimension

    def self.for_sku_as_of(sku_code, date = Date.current)
      where(sku_code: sku_code).effective_as_of(date).first
    end

    def self.latest_as_of(date = Date.current)
      where("ec_sku_costs.effective_on <= ?", date.to_date)
        .select("DISTINCT ON (ec_sku_costs.sku_code) ec_sku_costs.*")
        .order("ec_sku_costs.sku_code ASC, ec_sku_costs.effective_on DESC, ec_sku_costs.id DESC")
    end

    def self.latest_by_sku_as_of(sku_codes, date = Date.current)
      normalized_codes = Array(sku_codes).compact.uniq
      return none if normalized_codes.empty?

      where(sku_code: normalized_codes)
        .merge(latest_as_of(date))
    end

    def self.current_or_initialize(sku_code:, date: Date.current)
      for_sku_as_of(sku_code, date) || new(sku_code: sku_code, effective_on: date.to_date)
    end

    def customs_duty_cny
      return 0 unless purchase_price_cny && customs_duty_rate
      (purchase_price_cny * customs_duty_rate).round(4)
    end

    def import_vat_cny
      return 0 unless purchase_price_cny && import_vat_rate
      ((purchase_price_cny + customs_duty_cny) * import_vat_rate).round(4)
    end

    def goods_cost_cny
      [ purchase_price_cny, freight_to_by_cny, customs_misc_cny,
        customs_duty_cny, import_vat_cny ].sum(&:to_d).round(4)
    end

    def pkg_length_cm
      dimension_attribute(:inner_length_cm)
    end

    def pkg_length_cm=(value)
      assign_pending_dimension(:inner_length_cm, value)
    end

    def pkg_width_cm
      dimension_attribute(:inner_width_cm)
    end

    def pkg_width_cm=(value)
      assign_pending_dimension(:inner_width_cm, value)
    end

    def pkg_height_cm
      dimension_attribute(:inner_height_cm)
    end

    def pkg_height_cm=(value)
      assign_pending_dimension(:inner_height_cm, value)
    end

    def outer_length_cm
      dimension_attribute(:outer_length_cm)
    end

    def outer_length_cm=(value)
      assign_pending_dimension(:outer_length_cm, value)
    end

    def outer_width_cm
      dimension_attribute(:outer_width_cm)
    end

    def outer_width_cm=(value)
      assign_pending_dimension(:outer_width_cm, value)
    end

    def outer_height_cm
      dimension_attribute(:outer_height_cm)
    end

    def outer_height_cm=(value)
      assign_pending_dimension(:outer_height_cm, value)
    end

    # 包装内径优先；仅当尺寸全部缺失时才用 pkg_volume_override_l（Ozon 无尺寸时手填）
    def pkg_volume_l
      if pkg_length_cm && pkg_width_cm && pkg_height_cm
        (pkg_length_cm * pkg_width_cm * pkg_height_cm / 1000.0).round(4)
      elsif pkg_volume_override_l&.positive?
        pkg_volume_override_l.to_d
      else
        0
      end
    end

    def changed?
      super || pending_sku_dimension_changed?
    end

    private

    def set_default_effective_on
      self.effective_on ||= Date.current
    end

    def assign_pending_dimension(attribute, value)
      pending_sku_dimension_attributes[attribute] = Ec::SkuDimension.type_for_attribute(attribute.to_s).cast(value)
    end

    def dimension_attribute(attribute)
      return pending_sku_dimension_attributes[attribute] if pending_sku_dimension_attributes.key?(attribute)

      sku_dimension&.public_send(attribute)
    end

    def pending_sku_dimension_attributes
      @pending_sku_dimension_attributes ||= {}
    end

    def pending_sku_dimension_changed?
      pending_sku_dimension_attributes.any? do |attribute, value|
        sku_dimension&.public_send(attribute) != value
      end
    end

    def persist_pending_sku_dimension
      return if pending_sku_dimension_attributes.empty?

      dimension = sku_dimension || build_sku_dimension(sku_code: sku_code)
      dimension.assign_attributes(pending_sku_dimension_attributes)
      dimension.save! if dimension.new_record? || dimension.changed?
      pending_sku_dimension_attributes.clear
    end
  end
end
