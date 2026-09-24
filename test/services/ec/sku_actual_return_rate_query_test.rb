require "test_helper"

class Ec::SkuActualReturnRateQueryTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(5).upcase
    @time_zone = ActiveSupport::TimeZone["Asia/Shanghai"]
    @sku = Ec::Sku.create!(sku_code: "ACT-RETURN-#{@token}")
    @other_sku = Ec::Sku.create!(sku_code: "ACT-RETURN-OTHER-#{@token}")
    @store = Ec::Store.create!(
      platform: "wb",
      store_name: "Actual return WB #{@token}",
      company_type: "general"
    )
    @product = Ec::SkuProduct.create!(
      sku: @sku,
      store: @store,
      product_id: "71001#{@token.hex % 1_000}",
      platform_sku_id: "WB-IGNORED-#{@token}"
    )
    @other_product = Ec::SkuProduct.create!(
      sku: @other_sku,
      store: @store,
      product_id: "72001#{@token.hex % 1_000}",
      platform_sku_id: "OTHER-WB-#{@token}"
    )
    @orders = []
  end

  teardown do
    Ec::OrderItem.where(order_id: @orders.map(&:id)).delete_all
    Ec::Order.where(id: @orders.map(&:id)).delete_all
    Ec::OperationLog.where(record_type: "Ec::SkuProduct", record_id: [@product.id, @other_product.id]).delete_all
    Ec::OperationLog.where(record_type: "Ec::Store", record_id: @store.id).delete_all
    Ec::OperationLog.where(record_type: "Ec::Sku", record_id: [@sku.id, @other_sku.id]).delete_all
    Ec::SkuProduct.where(id: [@product.id, @other_product.id]).delete_all
    Ec::Store.where(id: @store.id).delete_all
    Ec::Sku.with_deleted.where(id: [@sku.id, @other_sku.id]).delete_all
  end

  test "calculates the WB returned-unit share across the last four completed weeks" do
    create_item(status: "delivered", quantity: 2, date: Date.new(2093, 8, 25))
    create_item(status: "returned", quantity: 1, date: Date.new(2093, 9, 1))
    create_item(status: "cancelled", quantity: 5, date: Date.new(2093, 9, 2))
    create_item(status: "processing", quantity: 4, date: Date.new(2093, 9, 3))
    create_item(status: "delivered", quantity: 3, date: Date.new(2093, 9, 4), product: @other_product)
    create_item(status: "returned", quantity: 6, date: Date.new(2093, 8, 23))

    payload = query

    assert_equal "wb", payload[:platform]
    assert_equal Date.new(2093, 8, 24), payload.dig(:period, :from_date)
    assert_equal Date.new(2093, 9, 20), payload.dig(:period, :to_date)
    assert_equal Date.new(2093, 9, 1), payload.dig(:period, :data_through)
    assert_equal 1, payload[:store_count]
    assert_equal 1, payload[:listing_count]
    assert_equal 3, payload.dig(:return_rate, :order_count)
    assert_equal 1, payload.dig(:return_rate, :return_count)
    assert_equal 0.3333333333.to_d, payload.dig(:return_rate, :rate)
  end

  test "returns an empty rate when there are no completed WB orders" do
    payload = query

    assert_equal 0, payload.dig(:return_rate, :order_count)
    assert_equal 0, payload.dig(:return_rate, :return_count)
    assert_nil payload.dig(:return_rate, :rate)
  end

  private

  def query
    Ec::SkuActualReturnRateQuery.run(
      sku: @sku,
      platform: "wb",
      today: Date.new(2093, 9, 21),
      time_zone: @time_zone
    )
  end

  def create_item(status:, quantity:, date:, product: @product)
    order = Ec::Order.create!(
      platform: "wb",
      store: @store,
      order_key: "ACT-RETURN-#{@token}-#{@orders.size}",
      order_status: status,
      ordered_at: @time_zone.local(date.year, date.month, date.day, 12)
    )
    @orders << order
    order.items.create!(
      platform: "wb",
      store: @store,
      platform_sku_id: product.product_id,
      quantity: quantity
    )
  end
end
