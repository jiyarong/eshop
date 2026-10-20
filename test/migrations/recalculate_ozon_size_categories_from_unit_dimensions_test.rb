require "test_helper"
require_relative "../../db/migrate/20261020013933_recalculate_ozon_size_categories_from_unit_dimensions"

class RecalculateOzonSizeCategoriesFromUnitDimensionsTest < ActiveSupport::TestCase
  self.use_transactional_tests = true

  test "backfills unit categories including missing values and can restore carton categories" do
    token = SecureRandom.hex(6).upcase
    dimensions = [24.5, 45, 221, nil, 0].each_with_index.map do |length, index|
      sku = Ec::Sku.create!(sku_code: "UNIT-MIGRATION-#{token}-#{index}")
      dimension = sku.create_dimension!(inner_length_cm: length, inner_width_cm: 9.2,
        inner_height_cm: 7, inner_box_weight_kg: 0.35, outer_length_cm: 48.5,
        outer_width_cm: 30, outer_height_cm: 51, outer_box_weight_kg: 14, outer_box_pcs: 40)
      dimension.update_columns(ozon_size_category: "kgt")
      dimension
    end
    migration = RecalculateOzonSizeCategoriesFromUnitDimensions.new

    2.times do
      migration.suppress_messages { migration.up }
      assert_equal %w[normal kgt oversize unknown unknown], dimensions.map { |dimension| dimension.reload.ozon_size_category }
    end

    migration.suppress_messages { migration.down }
    assert_equal ["kgt"] * 5, dimensions.map { |dimension| dimension.reload.ozon_size_category }
  end
end
