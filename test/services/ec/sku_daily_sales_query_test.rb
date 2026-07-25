require "test_helper"

class Ec::SkuDailySalesQueryTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(4).upcase
    @time_zone = Time.find_zone!("Asia/Shanghai")
    @store = Ec::Store.create!(
      platform: "ozon",
      store_name: "Daily sales #{@token}",
      company_type: "general",
      is_active: true
    )
    @sku = Ec::Sku.create!(sku_code: "DAILY-SALES-#{@token}", product_name: "Daily sales #{@token}")
    @wrong_sku = Ec::Sku.create!(sku_code: "DAILY-WRONG-#{@token}", product_name: "Wrong #{@token}")
    Ec::SkuProduct.create!(
      sku_code: @sku.sku_code,
      store: @store,
      product_id: "DAILY-PRODUCT-#{@token}",
      platform_sku_id: "DAILY-PLATFORM-#{@token}"
    )
  end

  teardown do
    Ec::OrderItem.joins(:order).where(ec_orders: { store_id: @store&.id }).delete_all
    Ec::OrderFulfillment.joins(:order).where(ec_orders: { store_id: @store&.id }).delete_all
    Ec::Order.where(store_id: @store&.id).delete_all
    Ec::SkuProduct.where(sku_code: @sku&.sku_code).delete_all
    Ec::Sku.with_deleted.where(id: [ @sku&.id, @wrong_sku&.id ].compact).delete_all
    Ec::Store.where(id: @store&.id).delete_all
  end

  test "groups sales by local date and hard sku product binding" do
    create_order("SALE", "2026-07-24 23:30", "delivered", 3)
    create_order("CANCELLED", "2026-07-24 12:00", "cancelled", 8)
    create_order("RETURNED", "2026-07-24 13:00", "returned", 5)

    result = Ec::SkuDailySalesQuery.new(
      sku_codes: [ @sku.sku_code ],
      from_date: Date.new(2026, 7, 24),
      to_date: Date.new(2026, 7, 24),
      time_zone: @time_zone
    ).call

    assert_equal({ [ Date.new(2026, 7, 24), @sku.sku_code ] => 3 }, result)
  end

  private

  def create_order(suffix, local_time, status, quantity)
    ordered_at = @time_zone.parse(local_time)
    external_id = "DAILY-#{suffix}-#{@token}"
    order = Ec::Order.create!(
      platform: "ozon",
      store: @store,
      external_order_id: external_id,
      external_order_number: external_id,
      order_key: "ozon:#{@store.id}:#{external_id}",
      order_status: status,
      ordered_at: ordered_at,
      synced_at: ordered_at
    )
    fulfillment = order.fulfillments.create!(
      platform: "ozon",
      store: @store,
      external_fulfillment_id: "#{external_id}-F",
      fulfillment_key: "ozon:#{@store.id}:#{external_id}-F",
      fulfillment_type: "fbo",
      status: status,
      synced_at: ordered_at
    )
    order.items.create!(
      fulfillment: fulfillment,
      platform: "ozon",
      store: @store,
      external_item_id: "#{external_id}-I",
      platform_sku_id: "DAILY-PLATFORM-#{@token}",
      sku_code: @wrong_sku.sku_code,
      product_name_source: "Daily sale",
      quantity: quantity,
      unit_price: 1,
      currency_code: "CNY",
      synced_at: ordered_at
    )
  end
end
