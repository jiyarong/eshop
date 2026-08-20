require "test_helper"

class SalesFunnelReports::SkuDailyTrendQueryTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(4).upcase
    @sku = Ec::Sku.create!(sku_code: "DAILY-FUNNEL-#{@token}", product_name: "日漏斗商品")
    @wb_account = RawWb::SellerAccount.create!(name: "Daily WB #{@token}", api_token: "token-#{@token}", company_type: :small)
    @ozon_account = RawOzon::SellerAccount.create!(company_name: "Daily Ozon #{@token}", client_id: "client-#{@token}", api_key: "key", company_type: :small)
    @wb_store = Ec::Store.create!(platform: "wb", store_name: "WB 店 #{@token}", company_type: "small", wb_raw_account_id: @wb_account.id)
    @ozon_store = Ec::Store.create!(platform: "ozon", store_name: "Ozon 店 #{@token}", company_type: "small", ozon_raw_account_id: @ozon_account.id)
    Ec::SkuProduct.create!(sku_code: @sku.sku_code, store: @wb_store, product_id: "71001")
    Ec::SkuProduct.create!(sku_code: @sku.sku_code, store: @ozon_store, product_id: "OZON-71001", platform_sku_id: "81001")
  end

  teardown do
    Ec::Snapshot.where(snapshot_type: Ec::InventorySnapshot.snapshot_type, sku_id: @sku&.id).delete_all
    RawWb::SalesFunnelDaily.where(account_id: @wb_account&.id).delete_all
    RawOzon::SalesFunnelDaily.where(account_id: @ozon_account&.id).delete_all
    Ec::SkuProduct.where(sku_code: @sku&.sku_code).delete_all
    Ec::Store.where(id: [@wb_store&.id, @ozon_store&.id].compact).delete_all
    Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
    @wb_account&.destroy!
    @ozon_account&.destroy!
  end

  test "returns one daily trend for every active listing store" do
    RawWb::SalesFunnelDaily.create!(
      account: @wb_account, stat_date: Date.new(2026, 8, 10), nm_id: 71001,
      open_card: 100, add_to_cart: 20, orders: 8, buyouts: 6, synced_at: Time.current
    )
    RawOzon::SalesFunnelDaily.create!(
      account: @ozon_account, stat_date: Date.new(2026, 8, 11), sku: 81001,
      hits_view: 200, hits_view_search: 100, hits_view_pdp: 50,
      position_category: 7.25, hits_tocart: 30, hits_tocart_pdp: 20,
      ordered_units: 12, delivered_units: 10, revenue: 1_500, synced_at: Time.current
    )
    Ec::Snapshot.create!(
      sku: @sku, snapshot_type: Ec::InventorySnapshot.snapshot_type,
      snapshot_date: Date.new(2026, 8, 11), content: {
        overview: { book_stock: 120 },
        distribution: { levels: [
          { store_id: @ozon_store.id, fulfillment_type: "fbo", quantity: 20 },
          { store_id: @ozon_store.id, fulfillment_type: "fbs", quantity: 5 },
          { store_id: @ozon_store.id, fulfillment_type: "inbound", quantity: 9 }
        ] }
      }
    )

    trends = query.call

    assert_equal ["ozon", "wb"], trends.map { |trend| trend[:platform] }
    assert_equal ["Ozon 店 #{@token}", "WB 店 #{@token}"], trends.map { |trend| trend[:store_name] }
    assert_equal SalesFunnelReports::ReportQueryRunner::OZON_COLUMNS.drop(2), trends.first[:metrics]
    assert_equal %i[position_category hits_view conv_tocart ordered_units revenue], trends.first[:default_metrics]
    assert_equal %i[open_card add_to_cart orders buyouts], trends.second[:default_metrics]
    assert_equal 4, trends.first[:rows].size
    assert_equal 1_500.0, trends.first[:rows].find { |row| row[:date] == "2026-08-11" }.dig(:values, :revenue)
    ozon_values = trends.first[:rows].find { |row| row[:date] == "2026-08-11" }.fetch(:values)
    assert_equal 7.25, ozon_values[:position_category]
    assert_equal 50.0, ozon_values[:search_to_card_conversion]
    assert_equal 40.0, ozon_values[:conv_tocart]
    assert_equal 60.0, ozon_values[:cart_to_order]
    assert_equal 6.0, ozon_values[:order_conversion]
    assert_equal 125.0, ozon_values[:average_price]
    assert_equal 10.0, ozon_values[:delivered_units]
    assert_equal 120, ozon_values[:total_ending_inventory]
    assert_equal 25, ozon_values[:store_ending_inventory]
    assert_equal 100.0, trends.second[:rows].find { |row| row[:date] == "2026-08-10" }.dig(:values, :open_card)
  end

  test "keeps listing cards when the selected period has no daily rows" do
    trends = query.call

    assert_equal 2, trends.size
    assert trends.all? { |trend| trend[:rows].all? { |row| row[:values].values.all?(&:nil?) } }
  end

  test "sorts stores by data coverage and then funnel volume" do
    RawWb::SalesFunnelDaily.create!(
      account: @wb_account, stat_date: Date.new(2026, 8, 9), nm_id: 71001,
      open_card: 10, add_to_cart: 2, orders: 1, buyouts: 1, synced_at: Time.current
    )
    RawWb::SalesFunnelDaily.create!(
      account: @wb_account, stat_date: Date.new(2026, 8, 10), nm_id: 71001,
      open_card: 10, add_to_cart: 2, orders: 1, buyouts: 1, synced_at: Time.current
    )
    RawOzon::SalesFunnelDaily.create!(
      account: @ozon_account, stat_date: Date.new(2026, 8, 11), sku: 81001,
      hits_view: 10_000, hits_tocart: 1_000, ordered_units: 100, revenue: 100_000, synced_at: Time.current
    )

    trends = query.call

    assert_equal ["wb", "ozon"], trends.map { |trend| trend[:platform] }
    assert_equal [2, 1], trends.map { |trend| trend[:data_days] }
  end

  private

  def query
    SalesFunnelReports::SkuDailyTrendQuery.new(
      sku: @sku,
      from_date: Date.new(2026, 8, 9),
      to_date: Date.new(2026, 8, 12)
    )
  end
end
