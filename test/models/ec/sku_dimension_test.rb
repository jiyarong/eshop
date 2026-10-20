require "test_helper"

class Ec::SkuDimensionTest < ActiveSupport::TestCase
  setup do
    @sku_code = "SKU-DIM-#{SecureRandom.hex(4).upcase}"
    Ec::Sku.create!(sku_code: @sku_code, product_name: @sku_code, is_active: true)
  end

  teardown do
    Ec::SkuDimension.where(sku_code: @sku_code).delete_all
    Ec::SkuCost.where(sku_code: @sku_code).delete_all
    Ec::Sku.with_deleted.where(sku_code: @sku_code).delete_all
  end

  test "sku cost dimension aliases persist to sku dimension" do
    cost = Ec::SkuCost.create!(
      sku_code: @sku_code,
      pkg_length_cm: 10,
      pkg_width_cm: 20,
      pkg_height_cm: 30,
      outer_length_cm: 12,
      outer_width_cm: 22,
      outer_height_cm: 32
    )

    dimension = Ec::SkuDimension.find_by!(sku_code: @sku_code)
    dimension.update!(
      inner_box_weight_kg: 1.25,
      outer_box_weight_kg: 8.5,
      outer_box_pcs: 6
    )
    assert_equal BigDecimal("10"), dimension.inner_length_cm
    assert_equal BigDecimal("20"), dimension.inner_width_cm
    assert_equal BigDecimal("30"), dimension.inner_height_cm
    assert_equal BigDecimal("12"), dimension.outer_length_cm
    assert_equal BigDecimal("22"), dimension.outer_width_cm
    assert_equal BigDecimal("32"), dimension.outer_height_cm
    assert_equal BigDecimal("1.25"), dimension.inner_box_weight_kg
    assert_equal BigDecimal("8.5"), dimension.outer_box_weight_kg
    assert_equal 6, dimension.outer_box_pcs
    assert_equal BigDecimal("6.0"), cost.reload.pkg_volume_l
  end

  test "persisted sku cost reports dimension-only changes as changed" do
    cost = Ec::SkuCost.create!(sku_code: @sku_code, purchase_price_cny: 1)
    cost.pkg_length_cm = 5
    cost.pkg_width_cm = 6
    cost.pkg_height_cm = 7

    assert cost.changed?
    cost.save!

    assert_equal BigDecimal("5"), cost.reload.pkg_length_cm
    assert_equal BigDecimal("0.21"), cost.pkg_volume_l
  end

  test "classifies a packaged unit independently of a multi-unit shipping carton" do
    dimension = Ec::SkuDimension.create!(sku_code: @sku_code,
      inner_length_cm: 24.5, inner_width_cm: 9.2, inner_height_cm: 7, inner_box_weight_kg: 0.35,
      outer_length_cm: 48.5, outer_width_cm: 30, outer_height_cm: 51, outer_box_weight_kg: 14, outer_box_pcs: 40)
    assert_equal Ec::SkuDimension::OZON_SIZE_CATEGORY_NORMAL, dimension.ozon_size_category

    dimension.update!(outer_length_cm: 221, outer_box_weight_kg: 121)
    assert_equal Ec::SkuDimension::OZON_SIZE_CATEGORY_NORMAL, dimension.reload.ozon_size_category

    dimension.update!(inner_length_cm: 45)
    assert_equal Ec::SkuDimension::OZON_SIZE_CATEGORY_KGT, dimension.reload.ozon_size_category

    dimension.update!(inner_length_cm: 221)
    assert_equal Ec::SkuDimension::OZON_SIZE_CATEGORY_OVERSIZE, dimension.reload.ozon_size_category

    dimension.update!(inner_length_cm: 24.5, inner_box_weight_kg: 121)
    assert_equal Ec::SkuDimension::OZON_SIZE_CATEGORY_OVERSIZE, dimension.reload.ozon_size_category
  end

  test "does not use complete carton values when a packaged unit value is missing or nonpositive" do
    unit = { inner_length_cm: 35, inner_width_cm: 11.5, inner_height_cm: 17.5, inner_box_weight_kg: 1.03 }
    dimension = Ec::SkuDimension.create!(sku_code: @sku_code, outer_length_cm: 40, outer_width_cm: 30, outer_height_cm: 20)
    dimension.update!(**unit, outer_box_weight_kg: 10)

    unit.each_key do |field|
      [nil, 0, -1].each do |value|
        dimension.update!(**unit.merge(field => value))
        assert_equal Ec::SkuDimension::OZON_SIZE_CATEGORY_UNKNOWN, dimension.reload.ozon_size_category
      end
    end
  end

  test "a complete packaged unit can be classified without carton data" do
    dimension = Ec::SkuDimension.create!(sku_code: @sku_code,
      inner_length_cm: 35, inner_width_cm: 11.5, inner_height_cm: 17.5, inner_box_weight_kg: 1.03)

    assert_equal Ec::SkuDimension::OZON_SIZE_CATEGORY_NORMAL, dimension.reload.ozon_size_category
  end

  test "sorts packaged unit sides before applying Ozon limits" do
    dimension = Ec::SkuDimension.create!(sku_code: @sku_code,
      inner_length_cm: 100, inner_width_cm: 130, inner_height_cm: 10, inner_box_weight_kg: 10)

    assert_equal Ec::SkuDimension::OZON_SIZE_CATEGORY_KGT, dimension.ozon_size_category

    dimension.update!(inner_length_cm: 10, inner_width_cm: 100, inner_height_cm: 130)
    assert_equal Ec::SkuDimension::OZON_SIZE_CATEGORY_KGT, dimension.reload.ozon_size_category
  end
end
