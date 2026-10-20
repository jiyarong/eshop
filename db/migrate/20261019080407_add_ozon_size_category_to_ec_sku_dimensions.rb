class AddOzonSizeCategoryToEcSkuDimensions < ActiveRecord::Migration[8.1]
  class MigrationSkuDimension < ActiveRecord::Base
    self.table_name = "ec_sku_dimensions"
  end

  UNKNOWN = "unknown".freeze
  NORMAL = "normal".freeze
  KGT = "kgt".freeze
  OVERSIZE = "oversize".freeze

  def up
    add_column :ec_sku_dimensions, :ozon_size_category, :string
    MigrationSkuDimension.reset_column_information
    MigrationSkuDimension.find_each do |dimension|
      dimension.update_columns(ozon_size_category: category_for(dimension))
    end
  end

  def down
    remove_column :ec_sku_dimensions, :ozon_size_category
  end

  private

  def category_for(dimension)
    values = [dimension.outer_length_cm, dimension.outer_width_cm, dimension.outer_height_cm, dimension.outer_box_weight_kg]
    return UNKNOWN if values.any? { |value| value.blank? || value.to_d <= 0 }

    length, width, height, weight = values.map(&:to_d)
    return OVERSIZE if length > 220 || width > 120 || height > 80 || weight > 120
    return KGT if length >= 45 || width >= 32 || height >= 32

    NORMAL
  end
end
