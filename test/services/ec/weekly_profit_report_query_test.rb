require "test_helper"

class Ec::WeeklyProfitReportQueryTest < ActiveSupport::TestCase
  RateStub = Struct.new(:rate_cny_rub, :rate_byn_rub)
  ServiceStub = Struct.new(:summary, :results, :unallocated)

  test "run returns wr payload with comparison data for previous period" do
    query = Ec::WeeklyProfitReportQuery.new(
      store_ref: "wb:1",
      from_date: Date.new(2026, 5, 18),
      to_date: Date.new(2026, 5, 24)
    )

    rates_by_week = {
      Date.new(2026, 5, 18) => RateStub.new(BigDecimal("10"), BigDecimal("5")),
      Date.new(2026, 5, 11) => RateStub.new(BigDecimal("10"), BigDecimal("5"))
    }
    current_service = ServiceStub.new(
      { total_after_tax: 88.5, total_goods_cost: 20.0 },
      [{ vendor_code: "SKU-1", nm_id: 123, after_tax: 88.5, goods_cost: 20.0 }],
      { "未归属费用" => 12.3 }
    )
    current_service.define_singleton_method(:call) { self }
    previous_service = ServiceStub.new(
      { total_after_tax: 70.0, total_goods_cost: 25.0 },
      [{ vendor_code: "SKU-1", nm_id: 123, after_tax: 70.0, goods_cost: 25.0 }],
      { "未归属费用" => 15.0 }
    )
    previous_service.define_singleton_method(:call) { self }
    services = {
      [Date.new(2026, 5, 18), Date.new(2026, 5, 24)] => current_service,
      [Date.new(2026, 5, 11), Date.new(2026, 5, 17)] => previous_service
    }

    query.define_singleton_method(:find_account!) { Struct.new(:id, :name).new(1, "WB Test Shop") }
    query.define_singleton_method(:account_payload) { |account| { id: account.id, name: account.name } }
    query.define_singleton_method(:rate_payload) { |rate| { rate_cny_rub: rate.rate_cny_rub, rate_byn_rub: rate.rate_byn_rub } }
    query.define_singleton_method(:build_service) do |rate, from_date: @from_date, to_date: @to_date|
      services.fetch([from_date, to_date])
    end

    original_find_by = Ec::WeeklyRate.method(:find_by)
    Ec::WeeklyRate.define_singleton_method(:find_by) do |week_start:|
      rates_by_week[week_start]
    end

    payload = query.run

    assert_equal "2026-05-11", payload.dig(:comparison, :period, :from_date)
    assert_equal "positive", payload.dig(:comparison, :summary, :total_after_tax, :semantic)
    assert_equal "negative", payload.dig(:comparison, :summary, :total_goods_cost, :semantic)
    assert_equal "positive", payload.dig(:comparison, :rows, "SKU-1", :after_tax, :semantic)
    assert_equal "positive", payload.dig(:comparison, :rows, "SKU-1", :goods_cost, :semantic)
    assert_equal "positive", payload.dig(:comparison, :extras, :unallocated, "未归属费用", :amount, :semantic)
  ensure
    Ec::WeeklyRate.define_singleton_method(:find_by, original_find_by)
  end

  test "run groups ozon unallocated comparison rows by type" do
    query = Ec::WeeklyProfitReportQuery.new(
      store_ref: "ozon:1",
      from_date: Date.new(2026, 5, 18),
      to_date: Date.new(2026, 5, 24)
    )

    rates_by_week = {
      Date.new(2026, 5, 18) => RateStub.new(BigDecimal("10"), nil),
      Date.new(2026, 5, 11) => RateStub.new(BigDecimal("10"), nil)
    }
    current_service = ServiceStub.new(
      { total_after_tax_profit: 88.5, unallocated_total: -8.0 },
      [{ sku_code: "SKU-OZ", ozon_sku_id: "OZ-1", after_tax_profit: 88.5 }],
      {
        total: -8.0,
        rows: [
          { type_id: 96, type_name: "AcceleratedReviewCollection", posting_number: "A-1", amount: 1.2 },
          { type_id: 96, type_name: "AcceleratedReviewCollection", posting_number: "A-2", amount: 2.3 },
          { type_id: 41, type_name: "PPC", posting_number: "A-3", amount: 4.0 },
          { type_id: 41, type_name: "PPC", posting_number: nil, amount: 5.0, orphaned: true }
        ]
      }
    )
    current_service.define_singleton_method(:call) { self }
    previous_service = ServiceStub.new(
      { total_after_tax_profit: 80.0, unallocated_total: -4.0 },
      [{ sku_code: "SKU-OZ", ozon_sku_id: "OZ-1", after_tax_profit: 80.0 }],
      {
        total: -4.0,
        rows: [
          { type_id: 96, type_name: "AcceleratedReviewCollection", posting_number: "B-1", amount: 1.0 },
          { type_id: 96, type_name: "AcceleratedReviewCollection", posting_number: "B-2", amount: 1.0 },
          { type_id: 41, type_name: "PPC", posting_number: nil, amount: 2.0, orphaned: true }
        ]
      }
    )
    previous_service.define_singleton_method(:call) { self }
    services = {
      [Date.new(2026, 5, 18), Date.new(2026, 5, 24)] => current_service,
      [Date.new(2026, 5, 11), Date.new(2026, 5, 17)] => previous_service
    }

    query.define_singleton_method(:find_account!) { Struct.new(:id, :company_name).new(1, "Ozon Test Shop") }
    query.define_singleton_method(:account_payload) { |account| { id: account.id, name: account.company_name } }
    query.define_singleton_method(:rate_payload) { |rate| { rate_cny_rub: rate.rate_cny_rub } }
    query.define_singleton_method(:build_service) do |rate, from_date: @from_date, to_date: @to_date|
      services.fetch([from_date, to_date])
    end

    original_find_by = Ec::WeeklyRate.method(:find_by)
    Ec::WeeklyRate.define_singleton_method(:find_by) do |week_start:|
      rates_by_week[week_start]
    end

    payload = query.run

    assert_equal "negative", payload.dig(:comparison, :extras, :unallocated, 96, :amount, :semantic)
    assert_equal 3.5, payload.dig(:comparison, :extras, :unallocated, 96, :amount, :current)
    assert_equal 2.0, payload.dig(:comparison, :extras, :unallocated, 96, :amount, :previous)
    assert_equal 5.0, payload.dig(:comparison, :extras, :unallocated, 41, :amount, :current)
    refute payload.dig(:comparison, :extras, :unallocated).key?("41|PPC|A-3")
  ensure
    Ec::WeeklyRate.define_singleton_method(:find_by, original_find_by)
  end
end
