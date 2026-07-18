module Ec
  class SkuCost < ApplicationRecord
    include Ec::Auditable

    self.table_name = 'ec_sku_costs'

    belongs_to :sku, class_name: 'Ec::Sku', foreign_key: :sku_code, primary_key: :sku_code
    has_one :sku_dimension, class_name: "Ec::SkuDimension", foreign_key: :sku_code, primary_key: :sku_code

    validates :sku_code, presence: true, uniqueness: true
    after_save :persist_pending_sku_dimension

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
