require "test_helper"

class Ec::SkuTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(4).upcase
    @category = Ec::SkuCategory.create!(code: "SKU-CAT-#{@token}", name: "SKU 测试类目")
  end

  teardown do
    Ec::Sku.with_deleted.where(sku_code: "SKU-MGMT-#{@token}").delete_all
    Ec::SkuCategory.where(id: @category.id).delete_all
  end

  test "stores ERP management fields" do
    sku = Ec::Sku.create!(
      sku_code: "sku-mgmt-#{@token}",
      product_name: "中文商品",
      product_name_ru: "Русский товар",
      sku_category: @category,
      color: "黑色",
      spec: "双支装",
      size: "20cm",
      weight_kg: 1.25,
      volume_l: 3.5,
      model: "M-100",
      quality_grade: "A",
      features: "耐磨",
      owner_name: "运营 A",
      is_active: true,
      memo: "手动录入"
    )

    assert_equal "SKU-MGMT-#{@token}", sku.sku_code
    assert_equal @category, sku.sku_category
    assert_equal "黑色", sku.color
    assert_equal 1.25.to_d, sku.weight_kg
    assert_equal 3.5.to_d, sku.volume_l
  end

  test "sku code cannot change after creation" do
    sku = Ec::Sku.create!(sku_code: "sku-mgmt-#{@token}")

    sku.sku_code = "RENAMED-#{@token}"

    assert_not sku.save
    assert_includes sku.errors.details[:sku_code], error: :immutable
    assert_equal "SKU-MGMT-#{@token}", sku.reload.sku_code
  end

  test "soft-deleted skus are hidden from default queries" do
    sku = Ec::Sku.create!(
      sku_code: "sku-mgmt-#{@token}",
      product_name: "中文商品",
      is_active: true
    )

    sku.destroy!

    assert_not_nil sku.deleted_at
    assert_nil Ec::Sku.find_by(sku_code: sku.sku_code)
    assert_equal sku.id, Ec::Sku.with_deleted.find_by!(sku_code: sku.sku_code).id
    assert_equal [sku.id], Ec::Sku.deleted.where(sku_code: sku.sku_code).pluck(:id)
  end
end
