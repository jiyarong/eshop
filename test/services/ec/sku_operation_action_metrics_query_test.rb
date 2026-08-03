require "test_helper"

class Ec::SkuOperationActionMetricsQueryTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(5).upcase
    @time_zone = Time.find_zone!("Asia/Shanghai")
    @account = RawWb::SellerAccount.create!(
      name: "Action metrics #{@token}",
      api_token: "token-#{@token}",
      company_type: "small"
    )
    @store = Ec::Store.create!(
      platform: "wb",
      store_name: "Action metrics #{@token}",
      company_type: "small",
      wb_raw_account_id: @account.id,
      is_active: true
    )
    @sku = Ec::Sku.create!(sku_code: "ACTION-METRICS-#{@token}", product_name: "Action metrics")
    @wrong_sku = Ec::Sku.create!(sku_code: "ACTION-WRONG-#{@token}", product_name: "Wrong")
    @product = Ec::SkuProduct.create!(
      sku: @sku,
      store: @store,
      product_id: "#{900_000_000 + rand(10_000)}"
    )
  end

  teardown do
    RawWb::SalesFunnelDaily.where(account_id: @account&.id).delete_all
    Ec::OrderItem.where(store_id: @store&.id).delete_all
    Ec::Order.where(store_id: @store&.id).delete_all
    Ec::SkuProduct.where(id: @product&.id).delete_all
    Ec::Sku.with_deleted.where(id: [ @sku&.id, @wrong_sku&.id ].compact).delete_all
    Ec::Store.where(id: @store&.id).delete_all
    RawWb::SellerAccount.where(id: @account&.id).delete_all
  end

  test "returns daily hard-bound sales and normalized WB funnel metrics" do
    date = Date.new(2026, 7, 20)
    create_order(date, quantity: 3, stored_sku_code: @wrong_sku.sku_code)
    RawWb::SalesFunnelDaily.create!(
      account: @account,
      stat_date: date,
      nm_id: @product.product_id,
      open_card: 40,
      add_to_cart: 10,
      orders: 4,
      orders_sum: 800,
      synced_at: Time.current
    )

    result = Ec::SkuOperationActionMetricsQuery.new(
      sku: @sku,
      from_date: date,
      to_date: date,
      time_zone: @time_zone
    ).call

    assert_equal 3, result.dig(:sales_by_day_and_platform, [ date, "wb" ])
    funnel = result.dig(:funnel_by_day_and_platform, [ date, "wb" ])
    assert_equal 40, funnel.fetch(:views).to_i
    assert_equal 10, funnel.fetch(:add_to_cart).to_i
    assert_equal 4, funnel.fetch(:funnel_orders).to_i
    assert_equal 800, funnel.fetch(:revenue).to_i
  end

  test "normalizes Ozon daily funnel metrics through platform sku id" do
    date = Date.new(2026, 7, 20)
    ozon_account = RawOzon::SellerAccount.create!(
      company_name: "Action metrics Ozon #{@token}",
      client_id: "ozon-#{@token}",
      api_key: "key-#{@token}",
      company_type: "small"
    )
    ozon_store = Ec::Store.create!(
      platform: "ozon",
      store_name: "Action metrics Ozon #{@token}",
      company_type: "small",
      ozon_raw_account_id: ozon_account.id,
      is_active: true
    )
    ozon_product = Ec::SkuProduct.create!(
      sku: @sku,
      store: ozon_store,
      product_id: "OZON-PRODUCT-#{@token}",
      platform_sku_id: "#{700_000_000 + rand(10_000)}"
    )
    RawOzon::SalesFunnelDaily.create!(
      account: ozon_account,
      stat_date: date,
      sku: ozon_product.platform_sku_id,
      hits_view: 50,
      session_view: 30,
      hits_tocart: 8,
      ordered_units: 5,
      revenue: 1_200,
      returns_count: 1,
      synced_at: Time.current
    )

    result = Ec::SkuOperationActionMetricsQuery.new(
      sku: @sku,
      from_date: date,
      to_date: date,
      time_zone: @time_zone
    ).call
    funnel = result.dig(:funnel_by_day_and_platform, [ date, "ozon" ])

    assert_equal 50, funnel.fetch(:views).to_i
    assert_equal 30, funnel.fetch(:sessions).to_i
    assert_equal 8, funnel.fetch(:add_to_cart).to_i
    assert_equal 5, funnel.fetch(:funnel_orders).to_i
    assert_equal 1, funnel.fetch(:returns).to_i
  ensure
    RawOzon::SalesFunnelDaily.where(account_id: ozon_account&.id).delete_all
    Ec::SkuProduct.where(id: ozon_product&.id).delete_all
    Ec::Store.where(id: ozon_store&.id).delete_all
    RawOzon::SellerAccount.where(id: ozon_account&.id).delete_all
  end

  private

  def create_order(date, quantity:, stored_sku_code:)
    ordered_at = @time_zone.local(date.year, date.month, date.day, 12)
    external_id = "ACTION-METRICS-#{@token}-#{date}"
    order = Ec::Order.create!(
      platform: "wb",
      store: @store,
      external_order_id: external_id,
      external_order_number: external_id,
      order_key: "wb:#{@store.id}:#{external_id}",
      order_status: "delivered",
      ordered_at: ordered_at,
      synced_at: ordered_at
    )
    order.items.create!(
      platform: "wb",
      store: @store,
      external_item_id: "#{external_id}-I",
      platform_sku_id: @product.product_id,
      sku_code: stored_sku_code,
      quantity: quantity,
      synced_at: ordered_at
    )
  end
end
