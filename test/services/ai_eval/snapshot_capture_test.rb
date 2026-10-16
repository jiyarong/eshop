require "test_helper"
require "tmpdir"
require "fileutils"

class AiEvalSnapshotCaptureTest < ActiveSupport::TestCase
  setup do
    @sku = Ec::Sku.create!(sku_code: "EVAL-CAPTURE-#{SecureRandom.hex(4)}", product_name: "Eval capture")
    @directory = Pathname(Dir.mktmpdir("ai-eval-capture"))
    @date = Date.new(2026, 10, 10)
  end

  teardown do
    Ec::Sku.with_deleted.where(id: @sku.id).delete_all
    FileUtils.remove_entry(@directory)
  end

  test "captures original envelopes and read-only supplemental context without Ec snapshots" do
    period = { from: "2026-09-28", to: "2026-10-04", as_of: @date.iso8601, time_zone: "Asia/Shanghai" }
    envelope = { schema_version: 3, sku_code: @sku.sku_code, period: period }
    sections = {
      base: { current_stage: "GRW", current_grade: "B" },
      inventory: { current_inventory_info: { values: { book_stock: 37, incoming_quantity: 200, daily_sales_velocity: 4, strict_forecast_daily_sales: 6, turnover_days: 9.25, turnover_days_with_procurement: 59.25, strict_forecast_cover_days: 37.0 / 6 } } },
      lifecycle: { summary: { values: { current_stage: "grw", inventory_cover_days: 9.25 } } },
      profit: { sku_profit_overview_per_week: { periods: [{ period_key: "P-1", values: { after_tax: 3 } }, { period_key: "P0", values: { after_tax: 4 } }] } }
    }
    unified = envelope.merge(categories: sections.to_h do |section, values|
      [section, { name: section.to_s, description: "captured field contract", raw_json: { data: envelope.merge(section => values) }, markdown: "original" }]
    end)
    sku_id = @sku.id
    builder = Object.new
    builder.define_singleton_method(:capture_for) { |sku:, snapshot_date:| { sku_id: sku_id, content: unified } }
    planner = Object.new
    planner.define_singleton_method(:call) { |sku:, period_start:| { cycle: { start: period_start.iso8601, end: (period_start + 6).iso8601 }, prior_plans: [] } }
    attributes = Object.new
    attributes.define_singleton_method(:call) { |sku:| { listings: [] } }
    listings = Object.new
    listings.define_singleton_method(:call) { |sku:, product_attributes:, platforms:| "#{platforms.first} original listing" }
    service = AiEval::SnapshotCapture.new(
      snapshot_builder: builder, planner_context_builder: planner, product_attributes_builder: attributes,
      listing_context_builder: listings, rule_scope: -> { [] }, clock: -> { Time.utc(2026, 10, 10) }
    )
    queries = []
    callback = ->(_name, _start, _finish, _id, payload) { queries << payload[:sql] }
    destination = @directory.join("snapshot")
    snapshot = ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      service.call(sku: @sku, snapshot_date: @date, write_to: destination)
    end

    assert queries.none? { |sql| sql.match?(/\A\s*(INSERT|UPDATE|DELETE|CREATE|ALTER|DROP)\b/i) }, queries.join("\n")
    assert_equal unified.deep_stringify_keys, snapshot.read("unified_snapshot.json")
    assert_equal "ozon original listing", snapshot.read("supplemental/listing_context.json")["ozon"]
    assert_equal [], snapshot.manifest["metadata"]["diagnosis_rules"]
    assert_equal "2026-10-10", snapshot.manifest["metadata"].dig("planner_context", "cycle", "start")
    assert_equal snapshot.documents, AiEval::Snapshot.load(destination).documents
    assert_raises(ArgumentError) { service.call(sku: @sku, snapshot_date: @date, write_to: destination) }

    cases = AiEval::SnapshotCaseTemplates.call(snapshot: snapshot, base_snapshot: "#{@sku.sku_code}/2026-10-10")
    assert_equal %w[stockout missing_profit clearance], cases.keys
    cases.each_value do |definition|
      result = AiEval::Materializer.call(definition, snapshot: snapshot)
      assert_equal [], result.metadata[:validation_errors]
    end
    stockout = AiEval::Materializer.call(cases.fetch("stockout"), snapshot: snapshot)
    assert_equal 2.0, stockout.document("v3/inventory_context.json").dig("data", "inventory", "current_inventory_info", "values", "strict_forecast_cover_days")
    missing_profit = AiEval::Materializer.call(cases.fetch("missing_profit"), snapshot: snapshot)
    assert_equal ["P0"], missing_profit.document("v3/profit_context.json").dig("data", "profit", "sku_profit_overview_per_week", "periods").map { |period| period["period_key"] }
  end
end
