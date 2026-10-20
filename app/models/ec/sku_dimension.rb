module Ec
  class SkuDimension < ApplicationRecord
    include Ec::Auditable

    self.table_name = "ec_sku_dimensions"

    OZON_SIZE_CATEGORY_UNKNOWN = "unknown".freeze
    OZON_SIZE_CATEGORY_NORMAL = "normal".freeze
    OZON_SIZE_CATEGORY_KGT = "kgt".freeze
    OZON_SIZE_CATEGORY_OVERSIZE = "oversize".freeze
    OZON_SIZE_CATEGORIES = [
      OZON_SIZE_CATEGORY_UNKNOWN,
      OZON_SIZE_CATEGORY_NORMAL,
      OZON_SIZE_CATEGORY_KGT,
      OZON_SIZE_CATEGORY_OVERSIZE
    ].freeze

    belongs_to :sku, class_name: "Ec::Sku", foreign_key: :sku_code, primary_key: :sku_code

    validates :sku_code, presence: true, uniqueness: true
    validates :ozon_size_category, inclusion: { in: OZON_SIZE_CATEGORIES }, allow_nil: true

    before_validation :calculate_ozon_size_category

    def inner_volume_l
      volume_l(inner_length_cm, inner_width_cm, inner_height_cm)
    end

    def outer_volume_l
      volume_l(outer_length_cm, outer_width_cm, outer_height_cm)
    end

    def calculated_ozon_size_category
      self.class.ozon_size_category_for(
        length: inner_length_cm,
        width: inner_width_cm,
        height: inner_height_cm,
        weight: inner_box_weight_kg
      )
    end

    def self.ozon_size_category_for(length:, width:, height:, weight:)
      # Ozon FBO uses fixed axis thresholds for KGT; weight is an upper-limit check.
      values = [length, width, height, weight]
      return OZON_SIZE_CATEGORY_UNKNOWN if values.any? { |value| value.blank? || value.to_d <= 0 }

      length, width, height, weight = values.map(&:to_d)
      return OZON_SIZE_CATEGORY_OVERSIZE if length > 220 || width > 120 || height > 80 || weight > 120
      return OZON_SIZE_CATEGORY_KGT if length >= 45 || width >= 32 || height >= 32

      OZON_SIZE_CATEGORY_NORMAL
    end

    private

    def calculate_ozon_size_category
      self.ozon_size_category = calculated_ozon_size_category
    end

    def volume_l(length_cm, width_cm, height_cm)
      return 0 if [ length_cm, width_cm, height_cm ].any?(&:blank?)

      (length_cm * width_cm * height_cm / 1000.0).round(4)
    end
  end
end
