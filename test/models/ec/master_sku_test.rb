require "test_helper"

class Ec::MasterSkuTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(4).upcase
  end

  teardown do
    Ec::Sku.with_deleted.where("sku_code LIKE ?", "%#{@token}%").delete_all
    Ec::MasterSku.where("master_sku_code LIKE ?", "%#{@token}%").delete_all if defined?(Ec::MasterSku)
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
end
