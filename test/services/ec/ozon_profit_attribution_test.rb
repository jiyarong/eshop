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
    RawOzon::AccrualByDay.where(account_id: @ozon_account.id).delete_all if @ozon_account
    RawOzon::PostingDestination.where(account_id: @ozon_account.id).delete_all if @ozon_account
    RawOzon::PerformanceSkuSpend.where(account_id: @ozon_account.id).delete_all if @ozon_account
    RawOzon::PostingItem.where(account_id: @ozon_account.id).delete_all if @ozon_account
    Ec::SkuProduct.joins(:store).where(ec_stores: { id: @store_ids }).delete_all if @store_ids.any?
    Ec::Store.where(id: @store_ids).delete_all if @store_ids.any?
    Ec::SkuCost.where(sku_code: @sku_codes).delete_all if @sku_codes.any?
    Ec::Sku.with_deleted.where(sku_code: @sku_codes).delete_all if @sku_codes.any?
    @ozon_account&.destroy
  end

  test "resolve_ad_cost_periods uses cached natural weeks when page queries disable syncing" do
    first_from = Date.new(2026, 6, 22)
    first_to = Date.new(2026, 6, 28)
    second_to = Date.new(2026, 7, 5)
    RawOzon::PerformanceSkuSpend.create!(
      account: @ozon_account,
      period_from: first_from,
      period_to: first_to,
      ad_type: "ppc",
      ozon_sku_id: rand(10_000_000..99_999_999),
      spend: 100,
      synced_at: Time.current
    )

    service = Ec::OzonProfitAttribution.new(
      account_id: @ozon_account.id,
      from_date: first_from,
      to_date: second_to,
      rate_cny_rub: 10,
      sync_missing_ad_costs: false
    )

    assert_equal [[first_from, first_to]], service.send(:resolve_ad_cost_periods, first_from, second_to)
  end

  test "resolve_ad_cost_periods keeps cache miss semantics when syncing is enabled" do
    first_from = Date.new(2026, 6, 22)
    first_to = Date.new(2026, 6, 28)
    second_to = Date.new(2026, 7, 5)
    RawOzon::PerformanceSkuSpend.create!(
      account: @ozon_account,
      period_from: first_from,
      period_to: first_to,
      ad_type: "ppc",
      ozon_sku_id: rand(10_000_000..99_999_999),
      spend: 100,
      synced_at: Time.current
    )

    service = Ec::OzonProfitAttribution.new(
      account_id: @ozon_account.id,
      from_date: first_from,
      to_date: second_to,
      rate_cny_rub: 10,
      sync_missing_ad_costs: true
    )

    assert_nil service.send(:resolve_ad_cost_periods, first_from, second_to)
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

  test "compute_counts uses posting item quantity for net sales and destination units" do
    ozon_sku = rand(10_000_000..99_999_999)
    posting_number = "posting-quantity-#{@token}"
    RawOzon::PostingItem.create!(
      account: @ozon_account,
      posting_number: posting_number,
      posting_type: "fbo",
      ozon_sku: ozon_sku,
      quantity: 3,
      raw_json: {}
    )
    create_accrual(ozon_sku, posting_number, amount: 100)
    create_accrual(ozon_sku, posting_number, amount: 200)
    service = Ec::OzonProfitAttribution.new(
      account_id: @ozon_account.id,
      from_date: Date.new(2026, 6, 29),
      to_date: Date.new(2026, 7, 5),
      rate_cny_rub: 10.0,
      sync_missing_ad_costs: false
    )
    service.send(:load_rows)
    service.instance_variable_set(:@destinations, { posting_number => false })

    service.send(:load_posting_quantities)
    service.send(:compute_counts)
    service.send(:split_by_destination)

    assert_equal 1, service.instance_variable_get(:@counts).dig(ozon_sku, :order_count)
    assert_equal 3, service.instance_variable_get(:@counts).dig(ozon_sku, :net_sales_count)
    assert_equal 3, service.instance_variable_get(:@dest_split).dig(ozon_sku, :export_count)
  end

  test "posting quantities and destinations are limited by accrual account period and SKU without literal posting lists" do
    sku_id = rand(10_000_000..99_999_999)
    posting = "posting-scope-#{@token}"
    old_posting = "posting-old-#{@token}"
    create_accrual(sku_id, posting)
    create_accrual(sku_id, old_posting, accrual_date: Date.new(2026, 6, 28))
    [ [ posting, sku_id, 4 ], [ posting, sku_id + 1, 99 ], [ old_posting, sku_id, 88 ] ].each do |number, sku, quantity|
      RawOzon::PostingItem.create!(account: @ozon_account, posting_number: number, posting_type: "fbo",
        ozon_sku: sku, quantity: quantity, raw_json: {})
    end
    [ posting, old_posting ].each do |number|
      RawOzon::PostingDestination.create!(account: @ozon_account, posting_number: number, is_belarus: true, synced_at: Time.current)
    end
    service = Ec::OzonProfitAttribution.new(account_id: @ozon_account.id,
      from_date: Date.new(2026, 6, 29), to_date: Date.new(2026, 7, 5), rate_cny_rub: 10, sync_missing_ad_costs: false)

    sql = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") { |*, payload| sql << payload[:sql] }
    service.send(:load_posting_quantities)
    service.send(:load_destinations)

    assert_equal({ [ sku_id, posting ] => 4 }, service.instance_variable_get(:@posting_quantities))
    assert_equal({ posting => true }, service.instance_variable_get(:@destinations))
    assert sql.any? { |query| query.include?("EXISTS") }
    assert sql.none? { |query| query.include?(posting) }, "posting numbers should stay in the database"
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
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
    store = Ec::Store.create!(
      platform: "ozon", store_name: "Ozon Cost #{sku_code}", company_type: "small",
      ozon_raw_account_id: @ozon_account.id, is_active: true
    )
    @store_ids << store.id
    Ec::SkuProduct.create!(
      sku_code: sku_code, store: store, product_id: "OZON-C-#{@token}", platform_sku_id: ozon_sku.to_s
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

  test "default sku mapping uses sku product binding and merges listings of one sku" do
    sku_code = "OZ-DEF-#{@token}"
    ozon_sku_a, ozon_sku_b, ozon_sku_unbound = Array.new(3) { rand(10_000_000..99_999_999) }
    @sku_codes << sku_code

    Ec::Sku.create!(sku_code: sku_code)
    Ec::SkuCost.create!(
      sku_code: sku_code, effective_on: Date.new(2026, 6, 29),
      purchase_price_cny: 12, customs_duty_rate: 0, import_vat_rate: 0
    )
    store = Ec::Store.create!(
      platform: "ozon", store_name: "Ozon Default #{sku_code}", company_type: "small",
      ozon_raw_account_id: @ozon_account.id, is_active: true
    )
    @store_ids << store.id
    Ec::SkuProduct.create!(sku_code: sku_code, store: store, product_id: "P-A-#{@token}",
                           platform_sku_id: ozon_sku_a.to_s, offer_id: "#{sku_code}-RED")
    Ec::SkuProduct.create!(sku_code: sku_code, store: store, product_id: "P-B-#{@token}",
                           platform_sku_id: ozon_sku_b.to_s, offer_id: "#{sku_code}-BLUE")
    # offer_id 恰好等于内部 SKU，但没有绑定，不能被归属
    RawOzon::PostingItem.create!(
      account: @ozon_account, posting_number: "posting-default-#{@token}", posting_type: "fbo",
      ozon_sku: ozon_sku_unbound, offer_id: sku_code, raw_json: {}
    )

    service = Ec::OzonProfitAttribution.new(
      account_id: @ozon_account.id,
      from_date: Date.new(2026, 7, 1),
      to_date: Date.new(2026, 7, 5),
      rate_cny_rub: 10.0,
      sync_missing_ad_costs: false
    )

    service.send(:load_sku_mappings)

    mapping = service.instance_variable_get(:@sku_to_code)
    assert_equal sku_code, mapping.fetch(ozon_sku_a)
    assert_equal sku_code, mapping.fetch(ozon_sku_b)
    assert_not mapping.key?(ozon_sku_unbound)
    assert_equal 12.0, service.instance_variable_get(:@cost_by_sku).dig(ozon_sku_b, :cost_cny)
  end

  test "filtered profit matches full attribution while loading only the bound SKU accruals" do
    code = "OZ-FILTER-#{@token}"
    @sku_codes << code
    Ec::Sku.create!(sku_code: code)
    store = Ec::Store.create!(platform: "ozon", store_name: code, company_type: "small", ozon_raw_account_id: @ozon_account.id)
    @store_ids << store.id
    sku_id = rand(10_000_000..99_999_999)
    Ec::SkuProduct.create!(sku_code: code, store: store, product_id: "P-#{@token}", platform_sku_id: sku_id.to_s)
    create_accrual(sku_id, "target-#{@token}", amount: 300)
    create_accrual(sku_id + 1, "other-#{@token}", amount: 900)
    create_accrual(nil, nil, type_id: 41, amount: -75)
    RawOzon::PerformanceSkuSpend.create!(account: @ozon_account, period_from: Date.new(2026, 6, 29),
      period_to: Date.new(2026, 7, 5), ad_type: "ppc", ozon_sku_id: sku_id, spend: 25, synced_at: Time.current)
    options = { account_id: @ozon_account.id, from_date: Date.new(2026, 6, 29), to_date: Date.new(2026, 7, 5),
      rate_cny_rub: 10, sync_missing_ad_costs: false }

    full = Ec::OzonProfitAttribution.new(**options).call
    filtered = Ec::OzonProfitAttribution.new(**options, sku_codes: [ code ]).call

    assert_equal full.results.select { |row| row[:sku_code] == code }, filtered.results
    assert_equal [ sku_id ], filtered.instance_variable_get(:@rows).map(&:ozon_sku_id)
    assert_equal 0.0, filtered.unallocated[:total]

    query = Ec::WeeklySummaryDeepQuery.new(from_date: options[:from_date], to_date: options[:to_date],
      rate: Struct.new(:rate_cny_rub, :rate_byn_rub).new(10, 3), sku_codes: [ code.downcase ], include_comparison: false)
    account_ids = []
    original_new = Ec::OzonProfitAttribution.method(:new)
    Ec::OzonProfitAttribution.define_singleton_method(:new) do |**arguments|
      account_ids << arguments.fetch(:account_id)
      original_new.call(**arguments)
    end
    query.run

    assert_equal [ @ozon_account.id ], account_ids
  ensure
    Ec::OzonProfitAttribution.define_singleton_method(:new, original_new) if original_new
  end

  private

  def create_accrual(sku_id, posting, **attributes)
    RawOzon::AccrualByDay.create!({ account: @ozon_account, ozon_sku_id: sku_id, posting_number: posting,
      accrual_date: Date.new(2026, 6, 29), accrued_category: "ITEM", type_id: 0, type_name: "SaleRevenue",
      amount: 100, synced_at: Time.current }.merge(attributes))
  end
end
