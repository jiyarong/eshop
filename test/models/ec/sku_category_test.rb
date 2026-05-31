require "test_helper"

class Ec::SkuCategoryTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(4).upcase
  end

  teardown do
    Ec::SkuCategory.where("code LIKE ?", "CAT-#{@token}%").delete_all if defined?(Ec::SkuCategory)
  end

  test "normalizes code and supports parent categories" do
    parent = Ec::SkuCategory.create!(code: " cat-#{@token}-1 ", name: "一级类目")
    child = Ec::SkuCategory.create!(code: "cat-#{@token}-2", name: "二级类目", parent: parent)

    assert_equal "CAT-#{@token}-1", parent.code
    assert_equal parent, child.parent
    assert_equal [child], parent.children.to_a
  end

  test "rejects categories deeper than three levels" do
    level1 = Ec::SkuCategory.create!(code: "CAT-#{@token}-1", name: "一级类目")
    level2 = Ec::SkuCategory.create!(code: "CAT-#{@token}-2", name: "二级类目", parent: level1)
    level3 = Ec::SkuCategory.create!(code: "CAT-#{@token}-3", name: "三级类目", parent: level2)

    level4 = Ec::SkuCategory.new(code: "CAT-#{@token}-4", name: "四级类目", parent: level3)

    assert_not level4.valid?
    assert_includes level4.errors[:parent], "最多支持三级类目"
  end

  test "rejects circular parent" do
    category = Ec::SkuCategory.create!(code: "CAT-#{@token}-1", name: "一级类目")
    category.parent = category

    assert_not category.valid?
    assert_includes category.errors[:parent], "不能选择自己或子级类目"
  end
end
