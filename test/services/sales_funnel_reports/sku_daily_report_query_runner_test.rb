require "test_helper"

class SalesFunnelReports::SkuDailyReportQueryRunnerTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(4).upcase
    @account = RawWb::SellerAccount.create!(name: "Daily report #{@token}", api_token: "token-#{@token}", company_type: :small)
    @store = Ec::Store.create!(platform: "wb", store_name: "Daily report #{@token}", company_type: "small", wb_raw_account_id: @account.id)
    @sku = Ec::Sku.create!(sku_code: "DAILY-REPORT-#{@token}", product_name: "日漏斗汇总商品")
    Ec::SkuProduct.create!(sku_code: @sku.sku_code, store: @store, product_id: "72001")
  end

  teardown do
    RawWb::SalesFunnelDaily.where(account_id: @account&.id).delete_all
    Ec::SkuProduct.where(sku_code: @sku&.sku_code).delete_all
    @store&.destroy!
    Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
    @account&.destroy!
  end

  test "aggregates daily rows into the existing weekly report shape" do
    create_daily(Date.new(2026, 8, 3), open_card: 100, carts: 20, orders: 8, amount: 800)
    create_daily(Date.new(2026, 8, 4), open_card: 50, carts: 10, orders: 4, amount: 400)
    create_daily(Date.new(2026, 7, 27), open_card: 60, carts: 6, orders: 2, amount: 200)

    report = SalesFunnelReports::SkuDailyReportQueryRunner.run(
      params: {
        store_ref: "wb:#{@account.id}",
        from_date: "2026-08-03",
        to_date: "2026-08-09",
        sku_codes: [@sku.sku_code]
      },
      today: Date.new(2026, 8, 12)
    )
    row = report[:rows].sole

    assert_equal @sku.sku_code, row[:sku_code]
    assert_equal BigDecimal("150"), row[:open_card]
    assert_equal BigDecimal("30"), row[:add_to_cart]
    assert_equal BigDecimal("20"), row[:conv_to_cart]
    assert_equal BigDecimal("12"), row[:orders]
    assert_equal BigDecimal("1200"), row[:orders_sum]
    assert_equal BigDecimal("500"), report.dig(:comparison, :rows, @sku.sku_code, :orders, :delta_pct)
    assert_equal Date.new(2026, 7, 27), report.dig(:comparison, :period, :from_date)
    assert_equal Date.new(2026, 8, 2), report.dig(:comparison, :period, :to_date)
  end

  test "accepts an arbitrary partial-week date range" do
    create_daily(Date.new(2026, 8, 3), open_card: 100, carts: 20, orders: 8, amount: 800)
    create_daily(Date.new(2026, 8, 4), open_card: 50, carts: 10, orders: 4, amount: 400)

    report = SalesFunnelReports::SkuDailyReportQueryRunner.run(
      params: {
        store_ref: "wb:#{@account.id}",
        from_date: "2026-08-03",
        to_date: "2026-08-08",
        sku_codes: [@sku.sku_code]
      },
      today: Date.new(2026, 8, 12)
    )

    assert_equal Date.new(2026, 8, 3), report.dig(:period, :from_date)
    assert_equal Date.new(2026, 8, 8), report.dig(:period, :to_date)
    assert_equal BigDecimal("12"), report[:rows].sole[:orders]
    assert_equal Date.new(2026, 7, 28), report.dig(:comparison, :period, :from_date)
    assert_equal Date.new(2026, 8, 2), report.dig(:comparison, :period, :to_date)
  end

  test "rejects an inverted date range" do
    error = assert_raises(ArgumentError) do
      SalesFunnelReports::SkuDailyReportQueryRunner.run(
        params: {
          store_ref: "wb:#{@account.id}",
          from_date: "2026-08-08",
          to_date: "2026-08-03",
          sku_codes: [@sku.sku_code]
        },
        today: Date.new(2026, 8, 12)
      )
    end

    assert_equal "invalid_date_range", error.message
  end

  private

  def create_daily(date, open_card:, carts:, orders:, amount:)
    RawWb::SalesFunnelDaily.create!(
      account: @account,
      stat_date: date,
      nm_id: 72001,
      open_card: open_card,
      add_to_cart: carts,
      orders: orders,
      orders_sum: amount,
      buyouts: orders - 1,
      buyouts_sum: amount - 100,
      synced_at: Time.current
    )
  end
end
