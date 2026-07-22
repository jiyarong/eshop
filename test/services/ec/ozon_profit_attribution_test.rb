require "test_helper"

class Ec::OzonProfitAttributionTest < ActiveSupport::TestCase
  AccrualRow = Struct.new(:type_id, :ozon_sku_id, :posting_number, :amount)

  setup do
    @token = SecureRandom.hex(4).upcase
    @sku_codes = []
    @store_ids = []
    @ozon_account = RawOzon::SellerAccount.create!(
      client_id: "ozon-cost-#{@token}",
      api_key: "ozon-api-#{@token}",
      company_name: "Ozon Cost #{@token}",
      company_type: "small",
      is_active: true
    )
  end

  teardown do
    RawOzon::PostingItem.where(account_id: @ozon_account.id).delete_all if @ozon_account
    Ec::SkuProduct.joins(:store).where(ec_stores: { id: @store_ids }).delete_all if @store_ids.any?
    Ec::Store.where(id: @store_ids).delete_all if @store_ids.any?
    Ec::SkuCost.where(sku_code: @sku_codes).delete_all if @sku_codes.any?
    Ec::Sku.with_deleted.where(sku_code: @sku_codes).delete_all if @sku_codes.any?
    @ozon_account&.destroy
  end

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

  test "load_sku_mappings uses latest cost effective on report week monday" do
    sku_code = "OZ-COST-#{@token}"
    ozon_sku = rand(10_000_000..99_999_999)
    @sku_codes << sku_code

    Ec::Sku.create!(sku_code: sku_code)
    Ec::SkuCost.create!(
      sku_code: sku_code,
      effective_on: Date.new(2026, 1, 1),
      purchase_price_cny: 10,
      customs_duty_rate: 0,
      import_vat_rate: 0
    )
    Ec::SkuCost.create!(
      sku_code: sku_code,
      effective_on: Date.new(2026, 6, 29),
      purchase_price_cny: 15,
      customs_duty_rate: 0,
      import_vat_rate: 0
    )
    Ec::SkuCost.create!(
      sku_code: sku_code,
      effective_on: Date.new(2026, 7, 6),
      purchase_price_cny: 20,
      customs_duty_rate: 0,
      import_vat_rate: 0
    )
    RawOzon::PostingItem.create!(
      account: @ozon_account,
      posting_number: "posting-#{@token}",
      posting_type: "fbo",
      ozon_sku: ozon_sku,
      offer_id: sku_code,
      raw_json: {}
    )

    service = Ec::OzonProfitAttribution.new(
      account_id: @ozon_account.id,
      from_date: Date.new(2026, 7, 1),
      to_date: Date.new(2026, 7, 5),
      rate_cny_rub: 10.0,
      sync_missing_ad_costs: false
    )

    service.send(:load_sku_mappings)

    assert_equal 15.0, service.instance_variable_get(:@cost_by_sku).dig(ozon_sku, :cost_cny)
  end

  test "sku filter resolves ozon sku through sku product binding" do
    sku_code = "OZ-BIND-#{@token}"
    ozon_sku = rand(10_000_000..99_999_999)
    @sku_codes << sku_code

    Ec::Sku.create!(sku_code: sku_code)
    Ec::SkuCost.create!(
      sku_code: sku_code,
      effective_on: Date.new(2026, 6, 29),
      purchase_price_cny: 12,
      customs_duty_rate: 0,
      import_vat_rate: 0
    )
    store = Ec::Store.create!(
      platform: "ozon",
      store_name: "Ozon Binding #{sku_code}",
      company_type: "small",
      ozon_raw_account_id: @ozon_account.id,
      is_active: true
    )
    @store_ids << store.id
    Ec::SkuProduct.create!(
      sku_code: sku_code,
      store: store,
      product_id: "OZON-P-#{@token}",
      platform_sku_id: ozon_sku.to_s,
      offer_id: "RAW-#{sku_code}"
    )
    RawOzon::PostingItem.create!(
      account: @ozon_account,
      posting_number: "posting-binding-#{@token}",
      posting_type: "fbo",
      ozon_sku: ozon_sku,
      offer_id: "RAW-#{sku_code}",
      raw_json: {}
    )

    service = Ec::OzonProfitAttribution.new(
      account_id: @ozon_account.id,
      from_date: Date.new(2026, 7, 1),
      to_date: Date.new(2026, 7, 5),
      rate_cny_rub: 10.0,
      sync_missing_ad_costs: false,
      sku_codes: [sku_code.downcase]
    )

    service.send(:load_sku_mappings)

    assert_equal sku_code, service.instance_variable_get(:@sku_to_code).fetch(ozon_sku)
    assert_equal 12.0, service.instance_variable_get(:@cost_by_sku).dig(ozon_sku, :cost_cny)
  end
end
