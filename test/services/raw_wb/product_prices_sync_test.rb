require "test_helper"

class RawWbProductPricesSyncTest < ActiveSupport::TestCase
  test "rounds calculated final price to the database precision" do
    sync = RawWb::DailySync.allocate
    sync.instance_variable_set(:@account, Struct.new(:id).new(789))
    product = Struct.new(:id).new(123)
    sync.define_singleton_method(:find_or_create_product) { |_nm_id, _vendor_code| product }
    response = {
      "nmID" => 456,
      "discount" => 15,
      "clubDiscount" => 0,
      "sizes" => [{ "price" => 10_985 }]
    }

    row = sync.send(:build_product_price, response)

    assert_equal 93.37, row[:final_price]
  end
end
