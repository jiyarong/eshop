require "test_helper"

class Ec::WeeklySummaryUnboundListingTest < ActiveSupport::TestCase
  RateStub = Struct.new(:rate_cny_rub, :rate_byn_rub)
  FakeWb = Struct.new(:results, :unallocated) { def call = self }
  FakeOzon = Struct.new(:results, :unallocated) { def call = self }
  FakeAccount = Struct.new(:id, :name, :company_name)

  setup do
    @rate = RateStub.new(BigDecimal("10"), BigDecimal("5"))
    # 1 BYN = 0.5 CNY, 1 RUB = 0.1 CNY
    @query = Ec::WeeklySummaryDeepQuery.new(
      from_date: Date.new(2026, 7, 6), to_date: Date.new(2026, 7, 12), rate: @rate, include_comparison: false
    )
  end

  test "wb rows of one sku are merged and unbound listings move into unallocated instead of sku rows" do
    wb_rows = [
      wb_row(nm_id: 1, vendor_code: "SKU-1", after_tax: 10.0),
      wb_row(nm_id: 2, vendor_code: "SKU-1", after_tax: 20.0),
      wb_row(nm_id: 3, vendor_code: nil, after_tax: 8.0)
    ]

    rows, unalloc = collect_with(wb: FakeWb.new(wb_rows, { "x" => 0.0 }), ozon: FakeOzon.new([], { total: 0.0 }))

    assert_equal ["SKU-1"], rows.map { |row| row[:sku] }.uniq
    assert_equal 1, rows.size
    assert_equal 2, rows.first[:net_sales] # 两个 Listing 的销量合并到同一 SKU 行
    assert_in_delta 15.0, rows.first[:after_tax], 0.001 # (10 + 20) BYN * 0.5
    assert_in_delta 4.0, unalloc[:wb], 0.001 # 未绑定 Listing 税后利润 8 BYN * 0.5
  end

  test "ozon unbound listings move into unallocated instead of being dropped" do
    ozon_rows = [
      ozon_row(sku_code: "SKU-2", after_tax_profit: 100.0),
      ozon_row(sku_code: nil, after_tax_profit: 50.0)
    ]

    rows, unalloc = collect_with(wb: FakeWb.new([], {}), ozon: FakeOzon.new(ozon_rows, { total: 0.0 }))

    assert_equal ["SKU-2"], rows.map { |row| row[:sku] }
    assert_in_delta 5.0, unalloc[:ozon], 0.001 # 50 RUB * 0.1
  end

  test "wb revenue is the pre-commission tax base and settlement is shown as revenue after commission" do
    # tax_base 100 BYN is what the buyer-facing price adds up to (sales minus returns); for_pay 78 BYN is after commission and acquiring
    wb_rows = [wb_row(nm_id: 1, vendor_code: "SKU-1", after_tax: 10.0, settlement: 78.0, tax_base: 100.0)]

    rows, = collect_with(wb: FakeWb.new(wb_rows, {}), ozon: FakeOzon.new([], { total: 0.0 }))

    assert_in_delta 50.0, rows.first[:revenue], 0.001 # 100 BYN * 0.5
    assert_in_delta 39.0, rows.first[:revenue_after_commission], 0.001 # 78 BYN * 0.5
  end

  test "wb commission and acquiring reach the sku row so pre-commission revenue minus both equals revenue after commission" do
    wb_rows = [wb_row(nm_id: 1, vendor_code: "SKU-1", after_tax: 10.0, settlement: 78.0, tax_base: 100.0, commission: 20.0, acquiring: 2.0)]

    rows, = collect_with(wb: FakeWb.new(wb_rows, {}), ozon: FakeOzon.new([], { total: 0.0 }))
    row = rows.first

    assert_in_delta 10.0, row[:commission_fee], 0.001 # 20 BYN * 0.5
    assert_in_delta 1.0, row[:payment_fee], 0.001 # 2 BYN * 0.5
    assert_in_delta row[:revenue_after_commission], row[:revenue] - row[:commission_fee] - row[:payment_fee], 0.001
  end

  test "wb revenue drops when returns exceed sales because tax base already nets returns" do
    wb_rows = [wb_row(nm_id: 1, vendor_code: "SKU-1", after_tax: 0.0, settlement: -20.0, tax_base: -30.0)]

    rows, = collect_with(wb: FakeWb.new(wb_rows, {}), ozon: FakeOzon.new([], { total: 0.0 }))

    assert_in_delta(-15.0, rows.first[:revenue], 0.001)
    assert_in_delta(-10.0, rows.first[:revenue_after_commission], 0.001)
  end

  test "ozon revenue stays pre-commission and revenue after commission also deducts acquiring like wb for_pay" do
    ozon_rows = [ozon_row(sku_code: "SKU-2", after_tax_profit: 0.0, sales_revenue: 1000.0, commission: -350.0, payment_fee: -20.0)]

    rows, = collect_with(wb: FakeWb.new([], {}), ozon: FakeOzon.new(ozon_rows, { total: 0.0 }))

    assert_in_delta 100.0, rows.first[:revenue], 0.001 # 1000 RUB * 0.1
    assert_in_delta 63.0, rows.first[:revenue_after_commission], 0.001 # (1000 - 350 - 20) RUB * 0.1
  end

  test "both revenue figures reach the deep rows and summary for a sku sold on both platforms" do
    wb_rows = [wb_row(nm_id: 1, vendor_code: "SKU-1", after_tax: 10.0, settlement: 78.0, tax_base: 100.0)]
    ozon_rows = [ozon_row(sku_code: "SKU-1", after_tax_profit: 100.0, sales_revenue: 1000.0, commission: -350.0, payment_fee: -20.0)]

    rows, unalloc = collect_with(wb: FakeWb.new(wb_rows, {}), ozon: FakeOzon.new(ozon_rows, { total: 0.0 }))
    aggregated = @query.send(:aggregate_rows_by_sku, rows)
    deep_rows = @query.send(:build_wsu_deep_row_hashes, aggregated, from_date: Date.new(2026, 7, 6), to_date: Date.new(2026, 7, 12))
    summary = @query.send(:build_wsu_deep_summary_hash, aggregated, unalloc, rate: @rate, from_date: Date.new(2026, 7, 6), to_date: Date.new(2026, 7, 12))

    assert_in_delta 150.0, deep_rows.first[:revenue], 0.001 # 50 + 100
    assert_in_delta 102.0, deep_rows.first[:revenue_after_commission], 0.001 # 39 + 63
    assert_in_delta 150.0, summary[:total_sales_revenue], 0.001
    assert_in_delta 102.0, summary[:total_revenue_after_commission], 0.001
    # ratios keep the pre-commission revenue as their base
    assert_in_delta((deep_rows.first[:after_tax].to_f / 150.0 * 100), deep_rows.first[:margin_pct].to_f, 0.01)
  end

  private

  def collect_with(wb:, ozon:)
    wb_account = FakeAccount.new(1, "WB shop", nil)
    ozon_account = FakeAccount.new(2, nil, "Ozon shop")
    replace_singleton(RawWb::SellerAccount, :all, -> { [wb_account] }) do
      replace_singleton(RawOzon::SellerAccount, :all, -> { [ozon_account] }) do
        replace_singleton(Ec::WbProfitAttribution, :new, ->(**) { wb }) do
          replace_singleton(Ec::OzonProfitAttribution, :new, ->(**) { ozon }) do
            @query.send(:collect_rows, Date.new(2026, 7, 6), Date.new(2026, 7, 12), @rate)
          end
        end
      end
    end
  end

  def replace_singleton(klass, name, impl)
    original = klass.method(name)
    klass.define_singleton_method(name) { |*args, **kwargs, &blk| impl.call(*args, **kwargs, &blk) }
    yield
  ensure
    klass.define_singleton_method(name, original)
  end

  def wb_row(nm_id:, vendor_code:, after_tax:, settlement: 0.0, tax_base: 0.0, commission: 0.0, acquiring: 0.0)
    {
      nm_id: nm_id, vendor_code: vendor_code, sales_qty: 1, return_qty: 0, settlement: settlement, tax_base: tax_base,
      commission: commission, acquiring: acquiring, ad: 0.0,
      goods_cost: 0.0, pre_tax: after_tax, after_tax: after_tax, delivery: 0.0, storage: 0.0
    }
  end

  def ozon_row(sku_code:, after_tax_profit:, sales_revenue: 0.0, commission: 0.0, payment_fee: 0.0)
    {
      sku_code: sku_code, sales_revenue: sales_revenue, commission: commission, payment_fee: payment_fee,
      ppc_cost: 0.0, promotion_cost: 0.0, goods_cost: 0.0,
      pre_tax_profit: after_tax_profit, after_tax_profit: after_tax_profit, net_sales_count: 1
    }
  end
end
