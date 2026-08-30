require "test_helper"

class ErpAI::V2::MarketingProfitabilityContextTest < ActiveSupport::TestCase
  class ProfitQueryFake
    attr_reader :calls

    def initialize(&response)
      @response = response
      @calls = []
    end

    def run(**arguments)
      calls << arguments
      @response.call(**arguments)
    end
  end

  setup do
    @token = SecureRandom.hex(4).upcase
    @week_start = Date.new(2100, 1, 4) + (@token.to_i(16) % 50_000).weeks
    @sku = Ec::Sku.create!(sku_code: "MARKETING-PROFIT-#{@token}", product_name: "Marketing profitability")
    @wb_account = RawWb::SellerAccount.create!(name: "Profit WB #{@token}", api_token: "wb-#{@token}", company_type: :small)
    @ozon_account = RawOzon::SellerAccount.create!(
      company_name: "Profit Ozon #{@token}", client_id: "profit-ozon-#{@token}", api_key: "key-#{@token}", company_type: :small
    )
    @wb_store = Ec::Store.create!(platform: "wb", store_name: "Profit WB #{@token}", company_type: :small, wb_raw_account_id: @wb_account.id)
    @ozon_store = Ec::Store.create!(platform: "ozon", store_name: "Profit Ozon #{@token}", company_type: :small, ozon_raw_account_id: @ozon_account.id)
    @unbound_store = Ec::Store.create!(platform: "wb", store_name: "Profit unbound #{@token}", company_type: :small)
    @wb_product = Ec::SkuProduct.create!(sku_code: @sku.sku_code, store: @wb_store, product_id: "WB-#{@token}")
    @ozon_product = Ec::SkuProduct.create!(sku_code: @sku.sku_code, store: @ozon_store, product_id: "OZON-#{@token}", platform_sku_id: "OZON-SKU-#{@token}")
    @unbound_product = Ec::SkuProduct.create!(sku_code: @sku.sku_code, store: @unbound_store, product_id: "UNBOUND-#{@token}")
    @rate = Ec::WeeklyRate.create!(week_start: @week_start, rate_cny_rub: 10, rate_byn_rub: 25)
  end

  teardown do
    Ec::SkuProduct.where(id: [ @wb_product&.id, @ozon_product&.id, @unbound_product&.id ]).delete_all
    Ec::Store.where(id: [ @wb_store&.id, @ozon_store&.id, @unbound_store&.id ]).delete_all
    RawWb::SellerAccount.where(id: @wb_account&.id).delete_all
    RawOzon::SellerAccount.where(id: @ozon_account&.id).delete_all
    Ec::WeeklyRate.where(id: @rate&.id).delete_all
    Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
  end

  test "converts and aggregates WB BYN and Ozon RUB metrics into CNY" do
    query = ProfitQueryFake.new do |store_ref:, **|
      store_ref.start_with?("wb:") ? wb_report : ozon_report
    end

    result = described_context(profit_query: query).call
    week = result.fetch(:weekly).sole

    assert_equal "available", week.fetch(:data_status)
    assert_equal "CNY", result.fetch(:currency)
    assert_equal 2, week.fetch(:source_store_count)
    assert_equal 5, week.fetch(:net_sales)
    assert_equal 300, week.fetch(:revenue)
    assert_equal 53, week.fetch(:ads)
    assert_equal 110, week.fetch(:goods_cost)
    assert_equal 60, week.fetch(:pre_tax)
    assert_equal 17.5, week.fetch(:tax)
    assert_equal 42.5, week.fetch(:after_tax)
    assert_equal 14.17, week.fetch(:margin_pct)
    assert_equal 8.5, week.fetch(:average_profit_per_order)
    assert_equal 17.67, week.fetch(:ad_ratio_pct)
    assert_equal 38.64, week.fetch(:cost_return_pct)
    assert_equal [ "ozon:#{@ozon_account.id}", "wb:#{@wb_account.id}" ], query.calls.map { |call| call.fetch(:store_ref) }.sort
    assert query.calls.all? { |call| call.fetch(:sku_codes) == [ @sku.sku_code ] && !call.fetch(:include_comparison) }
  end

  test "reports no records when active bound sources return no rows" do
    query = ProfitQueryFake.new { empty_report }

    week = described_context(profit_query: query).call.fetch(:weekly).sole

    assert_equal "no_records", week.fetch(:data_status)
    assert_equal 2, week.fetch(:source_store_count)
    assert_equal 2, query.calls.size
  end

  test "reports partial sources when one bound store is unavailable" do
    query = ProfitQueryFake.new do |store_ref:, **|
      raise ActiveRecord::RecordNotFound if store_ref.start_with?("wb:")

      ozon_report
    end

    week = described_context(profit_query: query).call.fetch(:weekly).sole

    assert_equal "partial_sources", week.fetch(:data_status)
    assert_equal 1, week.fetch(:source_store_count)
    assert_equal [ @wb_store.id ], week.fetch(:unavailable_store_ids)
    assert_equal 50, week.fetch(:revenue)
  end

  test "does not aggregate a cost metric when one source row is missing it" do
    query = ProfitQueryFake.new do |store_ref:, **|
      if store_ref.start_with?("wb:")
        {
          rows: [
            { net_qty: 1, settlement: 100, ad: 10, goods_cost: 20, pre_tax: 30, tax: 5, after_tax: 25 },
            { net_qty: 1, settlement: 50, ad: 5, goods_cost: nil, pre_tax: nil, tax: nil, after_tax: nil }
          ],
          meta: { rates: { rate_cny_rub: 10, rate_byn_rub: 25 } }
        }
      else
        empty_report
      end
    end

    week = described_context(profit_query: query).call.fetch(:weekly).sole

    assert_nil week.fetch(:goods_cost)
    assert_nil week.fetch(:pre_tax)
    assert_nil week.fetch(:tax)
    assert_nil week.fetch(:after_tax)
    assert_nil week.fetch(:margin_pct)
  end

  test "does not treat missing sales, revenue, or advertising values as zero" do
    query = ProfitQueryFake.new do |store_ref:, **|
      next empty_report unless store_ref.start_with?("wb:")

      {
        rows: [
          { net_qty: nil, settlement: nil, ad: nil, goods_cost: 20,
            pre_tax: 30, tax: 5, after_tax: 25 },
          { net_qty: 2, settlement: 100, ad: 10, goods_cost: 20,
            pre_tax: 30, tax: 5, after_tax: 25 }
        ],
        meta: { rates: { rate_cny_rub: 10, rate_byn_rub: 25 } }
      }
    end

    week = described_context(profit_query: query).call.fetch(:weekly).sole

    assert_nil week.fetch(:net_sales)
    assert_nil week.fetch(:revenue)
    assert_nil week.fetch(:ads)
    assert_nil week.fetch(:margin_pct)
    assert_nil week.fetch(:average_profit_per_order)
    assert_nil week.fetch(:ad_ratio_pct)
  end

  test "does not treat missing Ozon sales, revenue, or advertising values as zero" do
    query = ProfitQueryFake.new do |store_ref:, **|
      next empty_report if store_ref.start_with?("wb:")

      {
        rows: [
          { net_sales_count: nil, sales_revenue: nil, total_ad_cost: nil,
            goods_cost: -100, pre_tax_profit: 100, after_tax_profit: 50 },
          { net_sales_count: 1, sales_revenue: 500, total_ad_cost: -30,
            goods_cost: -100, pre_tax_profit: 100, after_tax_profit: 50 }
        ],
        meta: { rates: { rate_cny_rub: 10 } }
      }
    end

    week = described_context(profit_query: query).call.fetch(:weekly).sole

    assert_nil week.fetch(:net_sales)
    assert_nil week.fetch(:revenue)
    assert_nil week.fetch(:ads)
    assert_nil week.fetch(:margin_pct)
    assert_nil week.fetch(:average_profit_per_order)
    assert_nil week.fetch(:ad_ratio_pct)
  end

  test "accepts JSON-style string keys from a profit query" do
    query = ProfitQueryFake.new do |store_ref:, **|
      next empty_report unless store_ref.start_with?("wb:")

      {
        "rows" => [
          { "net_qty" => 2, "settlement" => 100, "ad" => 20, "goods_cost" => 40,
            "pre_tax" => 20, "tax" => 5, "after_tax" => 15 }
        ],
        "meta" => { "rates" => { "rate_cny_rub" => 10, "rate_byn_rub" => 25 } }
      }
    end

    week = described_context(profit_query: query).call.fetch(:weekly).sole

    assert_equal "available", week.fetch(:data_status)
    assert_equal 100, week.fetch(:revenue)
    assert_equal 37.5, week.fetch(:after_tax)
  end

  test "does not query sources without a weekly rate and marks future weeks partial" do
    @rate.destroy!
    missing_rate_query = ProfitQueryFake.new { raise "should not query without a rate" }

    unavailable_week = described_context(profit_query: missing_rate_query).call.fetch(:weekly).sole
    assert_equal "unavailable", unavailable_week.fetch(:data_status)
    assert_equal "missing_exchange_rate", unavailable_week.fetch(:reason)
    assert_empty missing_rate_query.calls

    partial_query = ProfitQueryFake.new { raise "should not query a partial week" }
    partial_week = described_context(profit_query: partial_query, today: @week_start + 3.days).call.fetch(:weekly).sole
    assert_equal true, partial_week.fetch(:is_partial)
    assert_equal "partial_week", partial_week.fetch(:data_status)
    assert_empty partial_query.calls
  end

  private

  def described_context(profit_query:, today: @week_start.end_of_week(:monday) + 1.day)
    ErpAI::V2::MarketingProfitabilityContext.new(
      sku: @sku,
      channels: [
        { platform: "wb", store_id: @wb_store.id, account_ref: "wb:#{@wb_account.id}" },
        { platform: "ozon", store_id: @ozon_store.id, account_ref: "ozon:#{@ozon_account.id}" },
        { platform: "wb", store_id: @unbound_store.id, account_ref: nil }
      ],
      period_from: @week_start,
      period_to: @week_start.end_of_week(:monday),
      today: today,
      profit_query: profit_query
    )
  end

  def wb_report
    {
      rows: [ { net_qty: 2, settlement: 100, ad: 20, goods_cost: 40, pre_tax: 20, tax: 5, after_tax: 15 } ],
      meta: { rates: { rate_cny_rub: 10, rate_byn_rub: 25 } }
    }
  end

  def ozon_report
    {
      rows: [ { net_sales_count: 3, sales_revenue: 500, total_ad_cost: -30, goods_cost: -100, pre_tax_profit: 100, after_tax_profit: 50 } ],
      meta: { rates: { rate_cny_rub: 10 } }
    }
  end

  def empty_report
    { rows: [], meta: { rates: { rate_cny_rub: 10, rate_byn_rub: 25 } } }
  end
end
