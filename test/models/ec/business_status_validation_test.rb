require "test_helper"

class Ec::BusinessStatusValidationTest < ActiveSupport::TestCase
  test "fulfillment rejects values outside the vocabulary" do
    fulfillment = Ec::OrderFulfillment.new(business_status: "bogus", return_business_status: "bogus")
    fulfillment.valid?

    assert_includes fulfillment.errors.attribute_names, :business_status
    assert_includes fulfillment.errors.attribute_names, :return_business_status
  end

  test "order rejects values outside the vocabulary" do
    order = Ec::Order.new(business_status: "bogus", return_business_status: "bogus")
    order.valid?

    assert_includes order.errors.attribute_names, :business_status
    assert_includes order.errors.attribute_names, :return_business_status
  end

  test "new records default to needs_review and none" do
    assert_equal "needs_review", Ec::OrderFulfillment.new.business_status
    assert_equal "none", Ec::OrderFulfillment.new.return_business_status
    assert_equal "needs_review", Ec::Order.new.business_status
    assert_equal "none", Ec::Order.new.return_business_status
  end
end
