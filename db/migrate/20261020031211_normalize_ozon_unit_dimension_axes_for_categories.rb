class NormalizeOzonUnitDimensionAxesForCategories < ActiveRecord::Migration[8.1]
  class MigrationSkuDimension < ActiveRecord::Base
    self.table_name = "ec_sku_dimensions"
  end

  UNKNOWN = "unknown".freeze
  NORMAL = "normal".freeze

  def up
    recalculate_categories(sorted: true)
  end

  def down
    recalculate_categories(sorted: false)
  end

  private

  def recalculate_categories(sorted:)
    MigrationSkuDimension.reset_column_information
    MigrationSkuDimension.find_each do |dimension|
      dimension.update_columns(ozon_size_category: category_for(dimension, sorted: sorted))
    end
  end

  def category_for(dimension, sorted:)
    dimensions = [dimension.inner_length_cm, dimension.inner_width_cm, dimension.inner_height_cm]
    weight = dimension.inner_box_weight_kg
    values = dimensions + [weight]
    return UNKNOWN if values.any? { |value| value.blank? || value.to_d <= 0 }

    length, width, height = dimensions.map(&:to_d)
    length, width, height = [length, width, height].sort.reverse if sorted
    weight = weight.to_d
    measurements = { length: length, width: width, height: height, weight: weight }
    Ec::SkuDimension::OZON_SIZE_LIMITS.each do |category, limits|
      return category.to_s if limits.any? { |axis, limit| measurements.fetch(axis) > limit }
    end

    NORMAL
  end
end
