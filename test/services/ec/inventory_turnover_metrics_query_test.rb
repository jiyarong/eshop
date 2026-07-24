require "test_helper"
require "securerandom"

class Ec::InventoryTurnoverMetricsQueryTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(4).upcase
    @sku_a = Ec::Sku.create!(sku_code: "TURN-A-#{@token}", product_name: "周转商品A")
    @sku_b = Ec::Sku.create!(sku_code: "TURN-B-#{@token}", product_name: "周转商品B")
    @sku_c = Ec::Sku.create!(sku_code: "TURN-C-#{@token}", product_name: "周转商品C")

    @account = RawOzon::SellerAccount.create!(
      company_name: "turnover-#{@token}",
      client_id: "client-#{@token}",
      api_key: "key-#{@token}",
      company_type: "small"
    )
    @store = Ec::Store.create!(
      platform: "ozon",
      store_name: "周转筛选店 #{@token}",
      company_type: "small",
      ozon_raw_account_id: @account.id,
      is_active: true
    )

    create_binding(@sku_a, "TURN-PROD-A-#{@token}", "TURN-SKU-A-#{@token}", "TURN-OFFER-A-#{@token}")
    create_binding(@sku_b, "TURN-PROD-B-#{@token}", "TURN-SKU-B-#{@token}", "TURN-OFFER-B-#{@token}")
    create_binding(@sku_c, "TURN-PROD-C-#{@token}", "TURN-SKU-C-#{@token}", "TURN-OFFER-C-#{@token}")

    create_batch(@sku_a, "TURN-BATCH-A-#{@token}", 30)
    create_batch(@sku_b, "TURN-BATCH-B-#{@token}", 43)
    create_batch(@sku_c, "TURN-BATCH-C-#{@token}", 15)

    create_order(@sku_a, "TURN-ORDER-A-#{@token}", "TURN-SKU-A-#{@token}", "TURN-OFFER-A-#{@token}", 14)
    create_order(@sku_b, "TURN-ORDER-B-#{@token}", "TURN-SKU-B-#{@token}", "TURN-OFFER-B-#{@token}", 28)

    RawOzon::Return.create!(
      account: @account,
      return_id: 40_000_000 + @token.to_i(16),
      return_schema: "FBO",
      return_type: "Return",
      posting_number: "TURN-ORDER-A-#{@token}",
      order_number: "TURN-ORDER-A-#{@token}",
      ozon_sku: 0,
      offer_id: "TURN-OFFER-A-#{@token}",
      product_name: "周转退货A",
      quantity: 1,
      raw_json: {},
      synced_at: Time.zone.parse("2026-06-30 10:00:00")
    )
  end

  teardown do
    Ec::OrderItem.joins(:order).where(ec_orders: { store_id: @store.id }).delete_all
    Ec::Order.where(store_id: @store.id).delete_all
    RawOzon::Return.where(account_id: @account.id).delete_all
    Ec::SkuBatch.where(sku_code: [@sku_a.sku_code, @sku_b.sku_code, @sku_c.sku_code]).delete_all
    Ec::SkuProduct.where(sku_code: [@sku_a.sku_code, @sku_b.sku_code, @sku_c.sku_code]).delete_all
    Ec::Store.where(id: @store.id).delete_all
    RawOzon::SellerAccount.where(id: @account.id).delete_all
    Ec::Sku.with_deleted.where(id: [@sku_a.id, @sku_b.id, @sku_c.id]).delete_all
  end

  test "computes batch book stock and turnover days for multiple skus" do
    Ec::SkuBatch.create!(
      sku_code: @sku_a.sku_code,
      batch_code: "TURN-INCOMING-A-#{@token}",
      status: "in_transit",
      batch_type: :normal,
      purchased_quantity: 12,
      received_quantity: 9,
      purchase_unit_price_cny: 1
    )

    metrics = Ec::InventoryTurnoverMetricsQuery.new(
      sku_codes: [@sku_a.sku_code, @sku_b.sku_code, @sku_c.sku_code],
      date_to: Date.new(2026, 7, 1),
      time_zone: ActiveSupport::TimeZone["Asia/Shanghai"]
    ).call

    expected_velocity_a = weighted_velocity_for(14)
    expected_velocity_b = weighted_velocity_for(28)

    assert_equal 17, metrics.dig(@sku_a.sku_code, :book_stock)
    assert_equal 15, metrics.dig(@sku_b.sku_code, :book_stock)
    assert_equal 15, metrics.dig(@sku_c.sku_code, :book_stock)

    assert_equal expected_velocity_a, metrics.dig(@sku_a.sku_code, :daily_sales_velocity)
    assert_equal expected_velocity_b, metrics.dig(@sku_b.sku_code, :daily_sales_velocity)
    assert_equal BigDecimal("0"), metrics.dig(@sku_c.sku_code, :daily_sales_velocity)
    assert_equal 9, metrics.dig(@sku_a.sku_code, :procurement_stock)

    assert_equal BigDecimal("17") / expected_velocity_a, metrics.dig(@sku_a.sku_code, :turnover_days)
    assert_equal BigDecimal("15") / expected_velocity_b, metrics.dig(@sku_b.sku_code, :turnover_days)
    assert_equal BigDecimal("26") / expected_velocity_a, metrics.dig(@sku_a.sku_code, :turnover_days_with_procurement)
    assert_equal BigDecimal("15") / expected_velocity_b, metrics.dig(@sku_b.sku_code, :turnover_days_with_procurement)
    assert_nil metrics.dig(@sku_c.sku_code, :turnover_days)
    assert_nil metrics.dig(@sku_c.sku_code, :turnover_days_with_procurement)
  end

  private

  def create_binding(sku, product_id, platform_sku_id, offer_id)
    Ec::SkuProduct.create!(
      sku_code: sku.sku_code,
      store: @store,
      product_id: product_id,
      platform_sku_id: platform_sku_id,
      offer_id: offer_id
    )
  end

  def create_batch(sku, batch_code, received_quantity)
    Ec::SkuBatch.create!(
      sku_code: sku.sku_code,
      batch_code: batch_code,
      status: "received",
      batch_type: :normal,
      purchased_quantity: received_quantity,
      received_quantity: received_quantity,
      purchase_unit_price_cny: 1
    )
  end

  def create_order(sku, external_id, platform_sku_id, offer_id, quantity)
    order = Ec::Order.create!(
      platform: "ozon",
      store: @store,
      external_order_id: external_id,
      external_order_number: external_id,
      order_key: "ozon:#{@store.id}:#{external_id}",
      order_status: "delivered",
      ordered_at: Time.zone.parse("2026-06-29 10:00:00"),
      synced_at: Time.zone.parse("2026-06-29 10:05:00")
    )

    order.items.create!(
      platform: "ozon",
      store: @store,
      external_item_id: "#{external_id}-I",
      platform_sku_id: platform_sku_id,
      offer_id: offer_id,
      product_name_source: sku.product_name,
      quantity: quantity,
      unit_price: 100,
      payout: 80,
      commission_amount: 10,
      discount_amount: 0,
      currency_code: "BYN"
    )
  end

  def weighted_velocity_for(quantity)
    quantity = BigDecimal(quantity.to_s)

    (quantity / BigDecimal("7") * BigDecimal("0.5")) +
      (quantity / BigDecimal("15") * BigDecimal("0.3")) +
      (quantity / BigDecimal("30") * BigDecimal("0.2"))
  end
end
