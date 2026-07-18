module Ec
  class SkuDimension < ApplicationRecord
    include Ec::Auditable

    self.table_name = "ec_sku_dimensions"

    belongs_to :sku, class_name: "Ec::Sku", foreign_key: :sku_code, primary_key: :sku_code

    validates :sku_code, presence: true, uniqueness: true

    def inner_volume_l
      volume_l(inner_length_cm, inner_width_cm, inner_height_cm)
    end

    def outer_volume_l
      volume_l(outer_length_cm, outer_width_cm, outer_height_cm)
    end

    private

    def volume_l(length_cm, width_cm, height_cm)
      return 0 if [ length_cm, width_cm, height_cm ].any?(&:blank?)

      (length_cm * width_cm * height_cm / 1000.0).round(4)
    end
  end
end
