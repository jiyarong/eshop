require "test_helper"

class Ec::SkuReturnItemsQueryTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(5).upcase
    @sku = Ec::Sku.create!(sku_code: "RETURN-LIST-#{@token}")
    @store = Ec::Store.create!(platform: "ozon", store_name: "Return list #{@token}", company_type: "general")
    @sku_product = Ec::SkuProduct.create!(
      sku: @sku, store: @store, product_id: "PRODUCT-#{@token}", platform_sku_id: "PSKU-#{@token}"
    )
    @order = create_order("delivered")
    @order_item = @order.items.create!(
      platform: "ozon", store: @store, platform_sku_id: @sku_product.platform_sku_id, quantity: 20
    )
    @returns = 11.times.map { |index| create_return(@order, @order_item, index, restockable: index.even?) }

    cancelled_order = create_order("cancelled")
    cancelled_item = cancelled_order.items.create!(
      platform: "ozon", store: @store, platform_sku_id: @sku_product.platform_sku_id, quantity: 1
    )
    @cancelled_return = create_return(cancelled_order, cancelled_item, 99, restockable: true)
  end

  teardown do
    return_ids = Ec::Return.where(store: @store).pluck(:id)
    Ec::ReturnItem.where(return_id: return_ids).delete_all
    Ec::Return.where(id: return_ids).delete_all
    Ec::OrderItem.joins(:order).where(ec_orders: { store_id: @store.id }).delete_all
    Ec::Order.where(store: @store).delete_all
    Ec::SkuProduct.where(store: @store).delete_all
    @store.delete
    Ec::Sku.with_deleted.where(id: @sku.id).delete_all
  end

  test "paginates ten rows and excludes cancelled orders" do
    first_page = Ec::SkuReturnItemsQuery.new(@sku, page: 1, restockable: nil).call
    second_page = Ec::SkuReturnItemsQuery.new(@sku, page: 2, restockable: nil).call

    assert_equal 11, first_page.dig(:pagination, :total_count)
    assert_equal 10, first_page[:rows].size
    assert_equal 1, second_page[:rows].size
    assert_not_includes first_page[:rows].map { |row| row[:id] }, @cancelled_return.items.sole.id
  end

  test "filters by restockable" do
    restockable = Ec::SkuReturnItemsQuery.new(@sku, page: 1, restockable: "true").call
    not_restockable = Ec::SkuReturnItemsQuery.new(@sku, page: 1, restockable: "false").call

    assert_equal 6, restockable.dig(:pagination, :total_count)
    assert restockable[:rows].all? { |row| row[:restockable] }
    assert_equal 5, not_restockable.dig(:pagination, :total_count)
    assert not_restockable[:rows].none? { |row| row[:restockable] }
  end

  private

  def create_order(status)
    Ec::Order.create!(
      platform: "ozon", store: @store, order_key: "#{status}-#{SecureRandom.hex(5)}",
      order_status: status, external_order_number: "ORDER-#{SecureRandom.hex(5)}"
    )
  end

  def create_return(order, order_item, index, restockable:)
    ec_return = Ec::Return.create!(
      platform: "ozon", store: @store, order: order, return_key: "RETURN-#{index}-#{@token}",
      return_type: "customer_return", external_return_id: "RETURN-#{index}-#{@token}",
      requested_at: Time.zone.parse("2026-08-01 10:00:00") + index.minutes
    )
    ec_return.items.create!(
      platform: "ozon", store: @store, sku_product: @sku_product, order_item: order_item,
      item_key: "ITEM-#{index}-#{@token}", platform_sku_id: @sku_product.platform_sku_id,
      quantity: 1, restockable: restockable
    )
    ec_return
  end
end
