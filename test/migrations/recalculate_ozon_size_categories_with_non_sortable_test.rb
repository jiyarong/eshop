require "test_helper"
require_relative "../../db/migrate/20261021060333_recalculate_ozon_size_categories_with_non_sortable"

class RecalculateOzonSizeCategoriesWithNonSortableTest < ActiveSupport::TestCase
  self.use_transactional_tests = true

  test "SQL matches canonical sorted categories and down restores the legacy tiers" do
    inputs = [[32, 45, 32, 10], [60, 120, 50, 35], [30, 30, 30, 36],
      [120, 220, 80, 120], [30, 30, 30, 121], [nil, 30, 30, 10]]
    dimensions = inputs.map do |length, width, height, weight|
      Ec::Sku.create!(sku_code: "CATEGORY-MIG-#{SecureRandom.hex(5).upcase}").create_dimension!(
        inner_length_cm: length, inner_width_cm: width, inner_height_cm: height, inner_box_weight_kg: weight)
    end
    migration = RecalculateOzonSizeCategoriesWithNonSortable.new
    migration.suppress_messages { migration.up }
    assert_equal %w[normal non_sortable kgt kgt oversize unknown], dimensions.map { |dimension| dimension.reload.ozon_size_category }
    migration.suppress_messages { migration.down }
    assert_equal %w[kgt kgt normal kgt oversize unknown], dimensions.map { |dimension| dimension.reload.ozon_size_category }
    migration.suppress_messages { migration.up }
    assert_equal %w[normal non_sortable kgt kgt oversize unknown], dimensions.map { |dimension| dimension.reload.ozon_size_category }
  end
end
