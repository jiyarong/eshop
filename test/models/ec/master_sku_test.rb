require "test_helper"

class Ec::MasterSkuTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(4).upcase
  end

  teardown do
    Ec::Sku.with_deleted.where("sku_code LIKE ?", "%#{@token}%").delete_all
    Ec::MasterSku.where("master_sku_code LIKE ?", "%#{@token}%").delete_all if defined?(Ec::MasterSku)
    Ec::Category.where(source: "test", source_id: category_source_ids).delete_all if defined?(Ec::Category)
  end

  test "groups skus under a product level master sku" do
    master = Ec::MasterSku.create!(
      master_sku_code: "yl-master-#{@token}",
      product_name: "壁挂毛巾架",
      product_name_ru: "Настенный держатель",
      is_active: true
    )
    sku = Ec::Sku.create!(
      master_sku: master,
      sku_code: "YL-MASTER-#{@token}-GLD",
      product_name: "金色毛巾架",
      product_name_ru: "Золотой держатель"
    )

    assert_equal "YL-MASTER-#{@token}", master.master_sku_code
    assert_equal master, sku.master_sku
    assert_includes master.skus, sku
  end

  test "stores shared platform category for child skus to read" do
    parent_category = Ec::Category.create!(
      source: "test",
      source_type: "category",
      source_id: category_source_id("parent"),
      origin_name: "Parent #{@token}",
      origin_language: "en",
      name_en: "Parent #{@token}"
    )
    child_category = Ec::Category.create!(
      source: "test",
      source_type: "subject",
      source_id: category_source_id("child"),
      parent: parent_category,
      origin_name: "Child #{@token}",
      origin_language: "en",
      name_en: "Child #{@token}"
    )
    master = Ec::MasterSku.create!(
      master_sku_code: "yl-master-category-#{@token}",
      product_name: "类目产品",
      ec_category: child_category,
      is_active: true
    )
    sku = Ec::Sku.create!(
      master_sku: master,
      sku_code: "YL-MASTER-CATEGORY-#{@token}-A",
      product_name: "类目 SKU"
    )

    assert_equal parent_category, master.primary_ec_category
    assert_equal child_category, master.secondary_ec_category
    assert_equal child_category, sku.ec_category
    assert_equal parent_category, sku.primary_ec_category
    assert_equal child_category, sku.secondary_ec_category
  end

  private

  def category_source_id(suffix)
    "#{@token}-#{suffix}"
  end

  def category_source_ids
    %w[parent child].map { |suffix| category_source_id(suffix) }
  end
end
