require "test_helper"

class SalesFunnelReports::ReportQueryRunnerTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(4).upcase
    @wb_account = RawWb::SellerAccount.create!(
      name: "Funnel WB #{@token}", api_token: "wb-#{@token}", is_active: true, company_type: :small
    )
    @ozon_account = RawOzon::SellerAccount.create!(
      company_name: "Funnel Ozon #{@token}", client_id: "ozon-#{@token}", api_key: "key-#{@token}", is_active: true, company_type: :small
    )
    @wb_store = Ec::Store.create!(platform: "wb", store_name: "Funnel WB #{@token}", company_type: "small", wb_raw_account_id: @wb_account.id, is_active: true)
    @ozon_store = Ec::Store.create!(platform: "ozon", store_name: "Funnel Ozon #{@token}", company_type: "small", ozon_raw_account_id: @ozon_account.id, is_active: true)
    @sku = Ec::Sku.create!(sku_code: "FUNNEL-#{@token}", product_name: "漏斗商品")
    Ec::SkuProduct.create!(sku_code: @sku.sku_code, store: @wb_store, product_id: "70001", platform_sku_id: "WB-IGNORED")
    Ec::SkuProduct.create!(sku_code: @sku.sku_code, store: @ozon_store, product_id: "OZON-PRODUCT", platform_sku_id: "80001")
  end

  teardown do
    RawWb::SalesFunnelPeriod.where(account_id: @wb_account&.id).delete_all
    RawOzon::SalesFunnelPeriod.where(account_id: @ozon_account&.id).delete_all
    Ec::SkuProduct.where(sku_code: @sku&.sku_code).delete_all
    Ec::Store.where(id: [@wb_store&.id, @ozon_store&.id].compact).delete_all
    Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
    @wb_account&.destroy!
    @ozon_account&.destroy!
  end

  test "aggregates complete WB weeks and filters through product_id" do
    create_wb_period(Date.new(2026, 7, 6), Date.new(2026, 7, 12), open_card: 100, carts: 20, orders: 10, amount: 1_000)
    create_wb_period(Date.new(2026, 7, 13), Date.new(2026, 7, 19), open_card: 200, carts: 30, orders: 15, amount: 2_000)

    report = run_report("wb:#{@wb_account.id}", sku_codes: [@sku.sku_code])
    row = report[:rows].sole

    assert_equal "wb", report.dig(:meta, :platform)
    assert_equal @sku.sku_code, row[:sku_code]
    assert_equal "漏斗商品", row[:product_name]
    assert_equal BigDecimal("300"), row[:open_card]
    assert_equal BigDecimal("50"), row[:add_to_cart]
    assert_equal BigDecimal("16.67"), row[:conv_to_cart]
    assert_equal BigDecimal("25"), row[:orders]
    assert_equal BigDecimal("3000"), row[:orders_sum]
  end

  test "aggregates complete Ozon weeks and filters through platform_sku_id" do
    create_ozon_period(Date.new(2026, 6, 29), Date.new(2026, 7, 5), views: 50, carts: 5, orders: 2, revenue: 250)
    create_ozon_period(Date.new(2026, 7, 6), Date.new(2026, 7, 12), views: 80, carts: 8, orders: 4, revenue: 400)
    create_ozon_period(Date.new(2026, 7, 13), Date.new(2026, 7, 19), views: 120, carts: 22, orders: 6, revenue: 600)

    report = run_report("ozon:#{@ozon_account.id}", sku_codes: [@sku.sku_code])
    row = report[:rows].sole

    assert_equal "ozon", report.dig(:meta, :platform)
    assert_equal @sku.sku_code, row[:sku_code]
    assert_equal "漏斗商品", row[:product_name]
    assert_equal BigDecimal("200"), row[:hits_view]
    assert_equal BigDecimal("30"), row[:hits_tocart]
    assert_equal BigDecimal("15"), row[:conv_tocart]
    assert_equal BigDecimal("10"), row[:ordered_units]
    assert_equal BigDecimal("1000"), row[:revenue]
    assert_equal Date.new(2026, 6, 22), report.dig(:comparison, :period, :from_date)
    assert_equal Date.new(2026, 7, 5), report.dig(:comparison, :period, :to_date)
    assert_equal BigDecimal("300"), report.dig(:comparison, :summary, :revenue, :delta_pct)
    assert_equal BigDecimal("400"), report.dig(:comparison, :rows, @sku.sku_code, :ordered_units, :delta_pct)
    assert_equal "negative", report.dig(:comparison, :rows, @sku.sku_code, :returns_count, :semantic)
    assert_equal "negative", report.dig(:comparison, :summary, :cancellations, :semantic)
  end

  test "rejects ranges whose boundaries are not a complete calendar week" do
    error = assert_raises(ArgumentError) do
      SalesFunnelReports::ReportQueryRunner.run(
        params: { store_ref: "wb:#{@wb_account.id}", from_date: "2026-07-07", to_date: "2026-07-19" },
        today: Date.new(2026, 7, 24)
      )
    end

    assert_equal "invalid_week_range", error.message
  end

  test "excludes stored period rows that are not bounded by a natural week" do
    create_wb_period(Date.new(2026, 7, 6), Date.new(2026, 7, 12), open_card: 100, carts: 20, orders: 10, amount: 1_000)
    RawWb::SalesFunnelPeriod.create!(
      account: @wb_account, period_start: Date.new(2026, 7, 7), period_end: Date.new(2026, 7, 12),
      nm_id: 70002, vendor_code: "PARTIAL-#{@token}", product_name: "非完整周商品",
      open_card: 500, add_to_cart: 100, orders: 50, orders_sum: 5_000, synced_at: Time.current
    )

    report = SalesFunnelReports::ReportQueryRunner.run(
      params: { store_ref: "wb:#{@wb_account.id}", from_date: "2026-07-06", to_date: "2026-07-12" },
      today: Date.new(2026, 7, 24)
    )

    assert_equal [@sku.sku_code], report[:rows].map { |row| row[:sku_code] }
  end

  test "does not expose platform identity or product name for unmatched rows" do
    RawOzon::SalesFunnelPeriod.create!(
      account: @ozon_account, period_start: Date.new(2026, 7, 6), period_end: Date.new(2026, 7, 12),
      sku: 89999, product_name: "Very long platform product name", hits_view: 50,
      hits_tocart: 5, ordered_units: 2, revenue: 200, synced_at: Time.current
    )

    report = SalesFunnelReports::ReportQueryRunner.run(
      params: { store_ref: "ozon:#{@ozon_account.id}", from_date: "2026-07-06", to_date: "2026-07-12" },
      today: Date.new(2026, 7, 24)
    )
    row = report[:rows].sole

    assert_equal "89999", row[:sku_code]
    assert_nil row[:product_name]
    assert_instance_of String, row[:sku_code]
    assert_not_includes row.values, 89999
    assert_not_includes row.values, "Very long platform product name"
  end

  private

  def run_report(store_ref, extra = {})
    SalesFunnelReports::ReportQueryRunner.run(
      params: { store_ref: store_ref, from_date: "2026-07-06", to_date: "2026-07-19" }.merge(extra),
      today: Date.new(2026, 7, 24)
    )
  end

  def create_wb_period(from, to, open_card:, carts:, orders:, amount:)
    RawWb::SalesFunnelPeriod.create!(
      account: @wb_account, period_start: from, period_end: to, nm_id: 70001,
      vendor_code: @sku.sku_code, product_name: "WB 漏斗商品", open_card: open_card,
      add_to_cart: carts, orders: orders, orders_sum: amount, buyouts: orders - 1,
      buyouts_sum: amount - 100, cancel_count: 1, cancel_sum: 100, synced_at: Time.current
    )
  end

  def create_ozon_period(from, to, views:, carts:, orders:, revenue:)
    RawOzon::SalesFunnelPeriod.create!(
      account: @ozon_account, period_start: from, period_end: to, sku: 80001,
      product_name: "Ozon 漏斗商品", hits_view: views, hits_tocart: carts,
      session_view: views / 2, ordered_units: orders, revenue: revenue,
      returns_count: 1, cancellations: 1, synced_at: Time.current
    )
  end
end
