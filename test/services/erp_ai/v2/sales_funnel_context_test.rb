require "test_helper"

class ErpAI::V2::SalesFunnelContextTest < ActiveSupport::TestCase
  test "groups daily funnel rows by natural week and store without comparison" do
    sku = Struct.new(:sku_code).new("SKU-CONTEXT")
    stores = [
      { ref: "wb:11", platform: "wb", name: "WB Store", label: "WB Store" },
      { ref: "ozon:22", platform: "ozon", name: "Ozon Store", label: "Ozon Store" }
    ]
    calls = []
    query_runner = Object.new
    query_runner.define_singleton_method(:run) do |params:, today:, include_comparison:|
      calls << { params: params, today: today, include_comparison: include_comparison }
      { rows: [{ source: params.fetch(:store_ref), sku_code: params.fetch(:sku_code) }] }
    end

    result = ErpAI::V2::SalesFunnelContext.new(
      sku: sku,
      period_from: Date.new(2026, 8, 3),
      period_to: Date.new(2026, 8, 16),
      store_options: stores,
      query_runner: query_runner
    ).call

    assert_equal 2, result.size
    assert_equal({ period_from: "2026-08-03", period_to: "2026-08-09" }, result.first.slice(:period_from, :period_to))
    assert_equal({ period_from: "2026-08-10", period_to: "2026-08-16" }, result.last.slice(:period_from, :period_to))
    assert_equal 4, calls.size
    assert calls.all? { |call| call.fetch(:include_comparison) == false }
    assert calls.all? { |call| call.dig(:params, :sku_code) == "SKU-CONTEXT" }

    wb_store, ozon_store = result.first.fetch(:stores)
    assert_equal({ store_ref: "wb:11", platform: "wb", store_id: 11, store_name: "WB Store" }, wb_store.except(:data))
    assert_equal "wb:11", wb_store.fetch(:data).sole.fetch(:source)
    assert_equal({ store_ref: "ozon:22", platform: "ozon", store_id: 22, store_name: "Ozon Store" }, ozon_store.except(:data))
    assert_equal "ozon:22", ozon_store.fetch(:data).sole.fetch(:source)
  end

  test "marks a store unavailable when its source disappears during the query" do
    sku = Struct.new(:sku_code).new("SKU-CONTEXT")
    stores = [
      { ref: "wb:11", platform: "wb", name: "WB Store", label: "WB Store" },
      { ref: "ozon:22", platform: "ozon", name: "Ozon Store", label: "Ozon Store" }
    ]
    query_runner = Object.new
    query_runner.define_singleton_method(:run) do |params:, **|
      raise ActiveRecord::RecordNotFound if params.fetch(:store_ref) == "wb:11"

      { rows: [ { sku_code: params.fetch(:sku_code) } ] }
    end

    stores_payload = ErpAI::V2::SalesFunnelContext.new(
      sku: sku,
      period_from: Date.new(2026, 8, 3),
      period_to: Date.new(2026, 8, 9),
      store_options: stores,
      query_runner: query_runner
    ).call.sole.fetch(:stores)

    assert_equal(
      { data_status: "unavailable", reason: "source_unavailable", data: [] },
      stores_payload.first.slice(:data_status, :reason, :data)
    )
    assert_equal "SKU-CONTEXT", stores_payload.last.fetch(:data).sole.fetch(:sku_code)
  end
end
