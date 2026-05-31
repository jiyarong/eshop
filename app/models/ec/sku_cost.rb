module Ec
  class SkuCost < ApplicationRecord
    self.table_name = 'ec_sku_costs'

    belongs_to :sku, class_name: 'Ec::Sku', foreign_key: :sku_code, primary_key: :sku_code

    validates :sku_code, presence: true, uniqueness: true

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

    # 包装尺寸优先；仅当尺寸全部缺失时才用 pkg_volume_override_l（Ozon 无尺寸时手填）
    def pkg_volume_l
      if pkg_length_cm && pkg_width_cm && pkg_height_cm
        (pkg_length_cm * pkg_width_cm * pkg_height_cm / 1000.0).round(4)
      elsif pkg_volume_override_l&.positive?
        pkg_volume_override_l.to_d
      else
        0
      end
    end
  end
end
