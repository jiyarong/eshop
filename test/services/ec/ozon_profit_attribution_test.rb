require "test_helper"

class Ec::OzonProfitAttributionTest < ActiveSupport::TestCase
  AccrualRow = Struct.new(:type_id, :ozon_sku_id, :posting_number, :amount)

  test "compute_counts keeps negative net sales count" do
    service = Ec::OzonProfitAttribution.new(
      account_id: 0,
      from_date: Date.new(2026, 6, 29),
      to_date: Date.new(2026, 7, 5),
      rate_cny_rub: 10.0,
      sync_missing_ad_costs: false
    )
    service.instance_variable_set(:@rows, [
      AccrualRow.new(0, 123, "ret-1", -100.0)
    ])

    service.send(:compute_counts)

    assert_equal(-1, service.instance_variable_get(:@counts).dig(123, :net_sales_count))
  end

  test "apply_profit_chain reverses goods cost for negative net sales" do
    service = Ec::OzonProfitAttribution.new(
      account_id: 0,
      from_date: Date.new(2026, 6, 29),
      to_date: Date.new(2026, 7, 5),
      rate_cny_rub: 10.0,
      sync_missing_ad_costs: false
    )
    fees = service.send(:zero_fees)
    fees[:sales_revenue] = -100.0
    service.instance_variable_set(:@fees, { 123 => fees })
    service.instance_variable_set(:@ppc_by_sku, Hash.new(0.0))
    service.instance_variable_set(:@promotion_by_sku, Hash.new(0.0))
    service.instance_variable_set(:@counts, { 123 => { order_count: 0, return_count: 1, net_sales_count: -1 } })
    service.instance_variable_set(:@dest_split, { 123 => { blr_sale: 0.0, blr_count: 0, export_count: -1 } })
    service.instance_variable_set(:@cost_by_sku, { 123 => { cost_cny: 30.0, import_vat_cny: 5.0 } })
    service.instance_variable_set(:@sku_to_code, { 123 => "SKU-NEG" })

    service.send(:apply_profit_chain)
    row = service.instance_variable_get(:@profit).fetch(123)

    assert_equal(-1, row[:net_sales_count])
    assert_in_delta 309.0, row[:goods_cost], 0.001
    assert_in_delta 209.0, row[:pre_tax_profit], 0.001
    assert_in_delta 157.5, row[:after_tax_profit], 0.001
  end
end
