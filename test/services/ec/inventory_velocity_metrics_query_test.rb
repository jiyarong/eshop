require "test_helper"
require "securerandom"

class Ec::InventoryVelocityMetricsQueryTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(4).upcase
    @sku = Ec::Sku.create!(sku_code: "VEL-#{@token}", product_name: "周转测试商品")
    @other_sku = Ec::Sku.create!(sku_code: "VEL2-#{@token}", product_name: "周转测试商品2")

    @account = RawOzon::SellerAccount.create!(
      company_name: "velocity-#{@token}",
      client_id: "client-#{@token}",
      api_key: "key-#{@token}",
      company_type: "small"
    )
    @store = Ec::Store.create!(
      platform: "ozon",
      store_name: "周转测试店 #{@token}",
      company_type: "small",
      ozon_raw_account_id: @account.id,
      is_active: true
    )

    Ec::SkuProduct.create!(
      sku_code: @sku.sku_code,
      store: @store,
      product_id: "VEL-PROD-#{@token}",
      platform_sku_id: "VEL-SKU-#{@token}",
      offer_id: "VEL-OFFER-#{@token}"
    )
    Ec::SkuProduct.create!(
      sku_code: @other_sku.sku_code,
      store: @store,
      product_id: "VEL2-PROD-#{@token}",
      platform_sku_id: "VEL2-SKU-#{@token}",
      offer_id: "VEL2-OFFER-#{@token}"
    )

    Ec::SkuBatch.create!(
      sku_code: @sku.sku_code,
      batch_code: "VEL-BATCH-#{@token}",
      status: "received",
      batch_type: :normal,
      purchased_quantity: 100,
      received_quantity: 100,
      purchase_unit_price_cny: 1
    )

    create_order(@sku, "VEL-30A-#{@token}", "delivered", Date.new(2026, 6, 2), 30)
    create_order(@sku, "VEL-15A-#{@token}", "processing", Date.new(2026, 6, 18), 15)
    create_order(@sku, "VEL-7A-#{@token}", "shipped", Date.new(2026, 6, 26), 7)
    create_order(@sku, "VEL-CANCEL-#{@token}", "cancelled", Date.new(2026, 6, 28), 99)
    create_order(@other_sku, "VEL2-7A-#{@token}", "delivered", Date.new(2026, 6, 29), 14)
  end

  teardown do
    Ec::OrderItem.joins(:order).where(ec_orders: { store_id: @store.id }).delete_all
    Ec::Order.where(store_id: @store.id).delete_all
    Ec::SkuBatch.where(sku_code: [@sku.sku_code, @other_sku.sku_code]).delete_all
    Ec::SkuProduct.where(sku_code: [@sku.sku_code, @other_sku.sku_code]).delete_all
    Ec::Store.where(id: @store.id).delete_all
    RawOzon::SellerAccount.where(id: @account.id).delete_all
    Ec::Sku.with_deleted.where(id: [@sku.id, @other_sku.id]).delete_all
  end

  test "computes weighted daily sales velocity in batch" do
    metrics = Ec::InventoryVelocityMetricsQuery.new(
      sku_codes: [@sku.sku_code, @other_sku.sku_code],
      date_to: Date.new(2026, 7, 1),
      time_zone: ActiveSupport::TimeZone["Asia/Shanghai"]
    ).call

    expected_sku_velocity =
      (BigDecimal("7") / BigDecimal("7") * BigDecimal("0.5")) +
      (BigDecimal("22") / BigDecimal("15") * BigDecimal("0.3")) +
      (BigDecimal("52") / BigDecimal("30") * BigDecimal("0.2"))
    expected_other_sku_velocity =
      (BigDecimal("14") / BigDecimal("7") * BigDecimal("0.5")) +
      (BigDecimal("14") / BigDecimal("15") * BigDecimal("0.3")) +
      (BigDecimal("14") / BigDecimal("30") * BigDecimal("0.2"))

    assert_equal expected_sku_velocity, metrics.dig(@sku.sku_code, :daily_sales_velocity)
    assert_equal expected_other_sku_velocity, metrics.dig(@other_sku.sku_code, :daily_sales_velocity)
    assert_nil metrics.dig(@sku.sku_code, :turnover_days)
    assert_nil metrics.dig(@other_sku.sku_code, :turnover_days)
  end

  private

  def create_order(sku, external_id, status, ordered_on, quantity)
    order = Ec::Order.create!(
      platform: "ozon",
      store: @store,
      external_order_id: external_id,
      external_order_number: external_id,
      order_key: "ozon:#{@store.id}:#{external_id}",
      order_status: status,
      ordered_at: Time.zone.parse("#{ordered_on} 10:00:00"),
      synced_at: Time.zone.parse("#{ordered_on} 10:05:00")
    )
    order.items.create!(
      platform: "ozon",
      store: @store,
      external_item_id: "#{external_id}-I",
      platform_sku_id: sku == @sku ? "VEL-SKU-#{@token}" : "VEL2-SKU-#{@token}",
      offer_id: sku == @sku ? "VEL-OFFER-#{@token}" : "VEL2-OFFER-#{@token}",
      product_name_source: "velocity item",
      quantity: quantity,
      unit_price: 100,
      payout: 80,
      commission_amount: 10,
      discount_amount: 0,
      currency_code: "BYN"
    )
  end
end
