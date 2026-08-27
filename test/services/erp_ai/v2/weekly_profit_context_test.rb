require "test_helper"

class ErpAI::V2::WeeklyProfitContextTest < ActiveSupport::TestCase
  test "groups the three report types by natural week and WR store" do
    sku = Struct.new(:sku_code).new("SKU-CONTEXT")
    stores = [
      { ref: "wb:11", platform: "wb", name: "WB Store", label: "WB Store" },
      { ref: "ozon:22", platform: "ozon", name: "Ozon Store", label: "Ozon Store" }
    ]
    wr_query = lambda do |store_ref:, from_date:, to_date:, sku_codes:, include_comparison:|
      assert_equal false, include_comparison
      {
        rows: [
          {
            source: store_ref,
            period: [from_date.iso8601, to_date.iso8601],
            sku_codes: sku_codes
          }
        ]
      }
    end
    summary_query = lambda do |from_date:, to_date:, sku_codes:, include_comparison:|
      assert_equal false, include_comparison
      { rows: [{ sku: sku_codes.sole, from: from_date.iso8601, to: to_date.iso8601 }] }
    end

    result = described_context(
      sku,
      store_options: stores,
      wr_query: query_double(wr_query),
      wsu_query: query_double(summary_query),
      wsu_deep_query: query_double(summary_query)
    ).call

    assert_equal 2, result.fetch(:wr).size
    assert_equal 2, result.fetch(:wsu).size
    assert_equal 2, result.fetch(:wsu_deep).size
    assert_equal({ period_from: "2026-07-27", period_to: "2026-08-02" }, result.fetch(:wsu).first.slice(:period_from, :period_to))
    assert_equal({ period_from: "2026-08-03", period_to: "2026-08-09" }, result.fetch(:wsu).last.slice(:period_from, :period_to))

    wb_store, ozon_store = result.fetch(:wr).first.fetch(:stores)
    assert_equal({ store_ref: "wb:11", platform: "wb", store_id: 11, store_name: "WB Store" }, wb_store.except(:data))
    assert_equal "wb:11", wb_store.fetch(:data).sole.fetch(:source)
    assert_equal({ store_ref: "ozon:22", platform: "ozon", store_id: 22, store_name: "Ozon Store" }, ozon_store.except(:data))
    assert_equal "ozon:22", ozon_store.fetch(:data).sole.fetch(:source)
    assert_equal "SKU-CONTEXT", result.fetch(:wsu_deep).last.fetch(:data).sole.fetch(:sku)
  end

  private

  def described_context(sku, **dependencies)
    ErpAI::V2::WeeklyProfitContext.new(
      sku: sku,
      period_from: Date.new(2026, 8, 3),
      period_to: Date.new(2026, 8, 16),
      **dependencies
    )
  end

  def query_double(callable)
    Object.new.tap do |query|
      query.define_singleton_method(:run) { |**args| callable.call(**args) }
    end
  end
end
