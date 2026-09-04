require "test_helper"

class RawWbProductPricesSyncTest < ActiveSupport::TestCase
  test "keeps WB price units and uses the discounted price" do
    sync = RawWb::DailySync.allocate
    sync.instance_variable_set(:@account, Struct.new(:id).new(789))
    product = Struct.new(:id).new(123)
    sync.define_singleton_method(:find_or_create_product) { |_nm_id, _vendor_code| product }
    response = {
      "nmID" => 456,
      "discount" => 15,
      "clubDiscount" => 0,
      "currencyIsoCode4217" => "BYN",
      "sizes" => [{ "price" => 10_985, "discountedPrice" => 9_337.25 }]
    }

    row = sync.send(:build_product_price, response)

    assert_equal 10_985, row[:price]
    assert_equal 9_337.25, row[:final_price]
    assert_equal "BYN", row[:currency_code]
  end
end
