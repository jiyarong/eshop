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

  def wb_row(nm_id:, vendor_code:, after_tax:)
    {
      nm_id: nm_id, vendor_code: vendor_code, sales_qty: 1, return_qty: 0, settlement: 0.0, ad: 0.0,
      goods_cost: 0.0, pre_tax: after_tax, after_tax: after_tax, delivery: 0.0, storage: 0.0
    }
  end

  def ozon_row(sku_code:, after_tax_profit:)
    {
      sku_code: sku_code, sales_revenue: 0.0, ppc_cost: 0.0, promotion_cost: 0.0, goods_cost: 0.0,
      pre_tax_profit: after_tax_profit, after_tax_profit: after_tax_profit, net_sales_count: 1
    }
  end
end
