require "test_helper"

class SalesFunnelReports::SkuFunnelAnalysisQueryTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(5).upcase
    @sku = Ec::Sku.create!(sku_code: "FUNNEL-V2-#{@token}", product_name: "Funnel V2")
    @wb_account = RawWb::SellerAccount.create!(name: "WB #{@token}", api_token: "token-#{@token}", company_type: :small)
    @ozon_account = RawOzon::SellerAccount.create!(company_name: "Ozon #{@token}", client_id: "client-#{@token}", api_key: "key", company_type: :small)
    @wb_store = Ec::Store.create!(platform: "wb", store_name: "WB #{@token}", company_type: "small", wb_raw_account_id: @wb_account.id)
    @ozon_store = Ec::Store.create!(platform: "ozon", store_name: "Ozon #{@token}", company_type: "small", ozon_raw_account_id: @ozon_account.id)
    @wb_product = Ec::SkuProduct.create!(sku_code: @sku.sku_code, store: @wb_store, product_id: "71001", product_name: "WB Listing")
    @ozon_product = Ec::SkuProduct.create!(sku_code: @sku.sku_code, store: @ozon_store, product_id: "OZ-#{@token}", platform_sku_id: "81001", product_name: "Ozon Listing")
  end

  teardown do
    Ec::OrderItem.where(store_id: [@wb_store&.id, @ozon_store&.id]).delete_all
    Ec::Order.where(store_id: [@wb_store&.id, @ozon_store&.id]).delete_all
    Ec::Snapshot.where(sku_id: @sku&.id).delete_all
    RawWb::SalesFunnelDaily.where(account_id: @wb_account&.id).delete_all
    RawOzon::SalesFunnelDaily.where(account_id: @ozon_account&.id).delete_all
    Ec::SkuProduct.where(id: [@wb_product&.id, @ozon_product&.id]).delete_all
    Ec::Store.where(id: [@wb_store&.id, @ozon_store&.id]).delete_all
    Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
    @wb_account&.destroy!
    @ozon_account&.destroy!
  end

  test "builds four equal periods and recomputes the cross-platform SKU funnel" do
    RawWb::SalesFunnelDaily.create!(account: @wb_account, stat_date: Date.new(2026, 8, 4), nm_id: 71001,
      open_card: 100, add_to_cart: 20, orders: 10, buyouts: 8, synced_at: Time.current)
    RawOzon::SalesFunnelDaily.create!(account: @ozon_account, stat_date: Date.new(2026, 8, 4), sku: 81001,
      hits_view: 1_000, hits_view_search: 400, hits_view_pdp: 300, hits_tocart: 90,
      hits_tocart_pdp: 60, ordered_units: 30, delivered_units: 20, synced_at: Time.current)
    create_order(@wb_store, "wb", "71001", "delivered", 6)
    create_order(@ozon_store, "ozon", "81001", "delivered", 14)
    unmatched_order = Ec::Order.create!(store: @wb_store, platform: "wb", order_key: "unmatched-#{@token}",
      order_status: "delivered", ordered_at: Time.find_zone!("Asia/Shanghai").local(2026, 8, 4, 13))
    Ec::OrderItem.create!(order: unmatched_order, store: @wb_store, platform: "wb", platform_sku_id: "WRONG",
      sku_code: @sku.sku_code, quantity: 99)
    create_inventory_snapshot

    result = query
    assert_equal %w[P-3 P-2 P-1 P0], result[:periods].map { |period| period[:key] }
    row = result[:periods].last[:sku_row]
    assert_equal 400, row[:product_card_views]
    assert_equal 80, row[:cart_additions]
    assert_equal BigDecimal("20"), row[:cart_rate]
    assert_equal 40, row[:orders]
    assert_equal BigDecimal("50"), row[:cart_to_order_rate]
    assert_equal 20, row[:conversions]
    assert_equal BigDecimal("5"), row[:visit_to_conversion_rate]
    assert_equal 20, row[:net_sales]
    assert_equal 150, row[:sku_ending_inventory]
    assert_equal "RUB", result[:store_groups].find { |group| group[:platform] == "wb" }.dig(:rows_by_period, "P0", :currency)
    assert_equal "RUB", result[:store_groups].find { |group| group[:platform] == "ozon" }.dig(:rows_by_period, "P0", :currency)
  end

  test "keeps platform-only values unavailable and distinguishes missing funnel data from zero" do
    RawOzon::SalesFunnelDaily.create!(account: @ozon_account, stat_date: Date.new(2026, 8, 3), sku: 81001,
      hits_view: 0, hits_view_search: 0, hits_view_pdp: 0, hits_tocart: 0, hits_tocart_pdp: 0,
      ordered_units: 0, synced_at: Time.current)
    create_inventory_snapshot

    result = query
    ozon = result[:store_groups].find { |group| group[:platform] == "ozon" }.dig(:rows_by_period, "P0")
    assert_includes ozon[:available_metrics], :ozon_total_views
    assert_not_includes ozon[:available_metrics], :wb_wishlist
    assert_nil ozon[:cart_rate]
    assert_equal 35, ozon[:store_ending_inventory]

    missing = result[:periods].first[:sku_row]
    assert_not_includes missing[:available_metrics], :product_card_views
  end

  test "builds a common daily trend with recomputed rates and hard-linked net sales" do
    RawWb::SalesFunnelDaily.create!(account: @wb_account, stat_date: Date.new(2026, 8, 4), nm_id: 71001,
      open_card: 100, add_to_cart: 20, orders: 10, synced_at: Time.current)
    RawOzon::SalesFunnelDaily.create!(account: @ozon_account, stat_date: Date.new(2026, 8, 4), sku: 81001,
      hits_view_pdp: 300, hits_tocart_pdp: 60, ordered_units: 30, synced_at: Time.current)
    create_order(@wb_store, "wb", "71001", "delivered", 6)
    create_order(@ozon_store, "ozon", "81001", "returned", 4)

    result = SalesFunnelReports::SkuCommonDailyTrendQuery.run(
      sku: @sku, from_date: Date.new(2026, 8, 3), to_date: Date.new(2026, 8, 9),
      time_zone: Time.find_zone!("Asia/Shanghai")
    )
    row = result[:rows].find { |item| item[:date] == "2026-08-04" }[:values]
    assert_equal 400.0, row[:product_card_views]
    assert_equal 80.0, row[:cart_additions]
    assert_equal 20.0, row[:cart_rate]
    assert_equal 40.0, row[:orders]
    assert_equal 50.0, row[:cart_to_order_rate]
    assert_equal 10.0, row[:conversions]
    assert_equal 2.5, row[:visit_to_conversion_rate]
    assert_equal 6.0, row[:net_sales]
  end

  private

  def query
    SalesFunnelReports::SkuFunnelAnalysisQuery.run(
      sku: @sku, from_date: Date.new(2026, 8, 3), to_date: Date.new(2026, 8, 9), time_zone: Time.find_zone!("Asia/Shanghai")
    )
  end

  def create_order(store, platform, platform_sku_id, status, quantity)
    order = Ec::Order.create!(store:, platform:, order_key: "#{platform}-#{@token}-#{quantity}", order_status: status,
      ordered_at: Time.find_zone!("Asia/Shanghai").local(2026, 8, 4, 12), completed_at: Time.find_zone!("Asia/Shanghai").local(2026, 8, 5, 12))
    Ec::OrderItem.create!(order:, store:, platform:, platform_sku_id:, quantity:)
  end

  def create_inventory_snapshot
    Ec::Snapshot.create!(sku: @sku, snapshot_type: Ec::InventorySnapshot.snapshot_type,
      snapshot_date: Date.new(2026, 8, 9), content: {
        overview: { book_stock: 150 },
        distribution: { levels: [
          { store_id: @wb_store.id, fulfillment_type: "fbw", quantity: 45 },
          { store_id: @ozon_store.id, fulfillment_type: "fbo", quantity: 30 },
          { store_id: @ozon_store.id, fulfillment_type: "fbs", quantity: 5 }
        ] }
      })
  end
end
