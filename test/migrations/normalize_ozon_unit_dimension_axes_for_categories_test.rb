require "test_helper"
require_relative "../../db/migrate/20261020031211_normalize_ozon_unit_dimension_axes_for_categories"

class NormalizeOzonUnitDimensionAxesForCategoriesTest < ActiveSupport::TestCase
  self.use_transactional_tests = true

  test "normalizes axes before recalculating and restores the previous axis rule on down" do
    token = SecureRandom.hex(6).upcase
    dimension = Ec::Sku.create!(sku_code: "UNIT-AXIS-MIGRATION-#{token}")
      .create_dimension!(inner_length_cm: 100, inner_width_cm: 130, inner_height_cm: 10,
        inner_box_weight_kg: 10, outer_length_cm: 40, outer_width_cm: 30, outer_height_cm: 20,
        outer_box_weight_kg: 8, outer_box_pcs: 1)
    dimension.update_columns(ozon_size_category: "oversize")
    migration = NormalizeOzonUnitDimensionAxesForCategories.new

    migration.suppress_messages { migration.up }
    assert_equal "kgt", dimension.reload.ozon_size_category

    migration.suppress_messages { migration.down }
    assert_equal "oversize", dimension.reload.ozon_size_category
  end
end
