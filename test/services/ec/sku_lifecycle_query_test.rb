require "test_helper"

class Ec::SkuLifecycleQueryTest < ActiveSupport::TestCase
  test "shows twelve timeline positions by default" do
    assert_equal 12, Ec::SkuLifecycleQuery::DEFAULT_VISIBLE_EVENT_COUNT
  end

  setup do
    @sku = Ec::Sku.create!(sku_code: "LIFECYCLE-QUERY-#{SecureRandom.hex(6)}")
  end

  teardown do
    Ec::SkuLifecycleEvent.where(sku_id: @sku.id).delete_all
    Ec::Snapshot.where(sku_id: @sku.id).delete_all
    Ec::SkuBatch.where(sku_code: @sku.sku_code).delete_all
    Ec::Sku.with_deleted.where(id: @sku.id).delete_all
  end

  test "returns an explicit unsold state without lifecycle days" do
    result = Ec::SkuLifecycleQuery.new(@sku, user_today: Date.new(2026, 8, 1),
      time_zone: Time.find_zone!("Asia/Shanghai")).call

    assert_equal false, result[:sold]
    assert_nil result.dig(:summary, :lifecycle_days)
    assert_equal :unsold, result[:timeline_nodes].first[:kind]
    assert_equal :current, result[:timeline_nodes].last[:kind]
  end

  test "adds stockout-adjusted sales and inventory cover without replacing existing metrics" do
    @sku.batches.create!(batch_code: "LIFECYCLE-DYNAMIC-#{SecureRandom.hex(4)}", batch_type: :normal,
      status: "received", purchased_quantity: 70, received_quantity: 70,
      received_on: Date.new(2026, 7, 20), purchase_unit_price_cny: 1)
    (Date.new(2026, 7, 25)..Date.new(2026, 7, 31)).each do |date|
      Ec::Snapshot.create!(sku: @sku, snapshot_type: "inventory", snapshot_date: date,
        content: { overview: { daily_sales: 7, out_of_stock: false } })
    end

    result = Ec::SkuLifecycleQuery.new(@sku, user_today: Date.new(2026, 8, 1),
      time_zone: Time.find_zone!("Asia/Shanghai")).call

    assert_equal BigDecimal("7"), result.dig(:summary, :stockout_adjusted_daily_sales)
    assert_equal BigDecimal("10"), result.dig(:summary, :stockout_adjusted_inventory_cover_days)
    assert result.dig(:summary, :daily_sales_velocity)
  end

  test "keeps the first sale and latest events with one collapsed node" do
    first = create_event("first_sale", Time.zone.parse("2026-01-01"), first_sale_content)
    7.times do |index|
      create_event("marketing_state_changed", Time.zone.parse("2026-02-#{format('%02d', index + 1)}"),
        { to_grade: "A", to_stage: "grw", initial_state: index.zero? })
    end
    query = Ec::SkuLifecycleQuery.new(@sku, user_today: Date.new(2026, 8, 1),
      time_zone: Time.find_zone!("Asia/Shanghai"), visible_event_count: 5)

    nodes = query.send(:timeline_nodes, @sku.lifecycle_events.chronological.to_a, first)

    assert_equal first, nodes.first[:event]
    assert_equal :collapsed, nodes.second[:kind]
    assert_equal 4, nodes.second[:count]
    assert_equal :current, nodes.last[:kind]
  end

  test "keeps replenishment events out of the lifecycle timeline" do
    first = create_event("first_sale", Time.zone.parse("2026-01-01"), first_sale_content)
    replenishment = create_event("replenishment", Time.zone.parse("2026-02-01"),
      { platform: "ozon", quantity: 50 })
    query = Ec::SkuLifecycleQuery.new(@sku, user_today: Date.new(2026, 8, 1),
      time_zone: Time.find_zone!("Asia/Shanghai"))

    nodes = query.send(:timeline_nodes, @sku.lifecycle_events.chronological.to_a, first)

    assert_not_includes nodes.filter_map { |node| node[:event] }, replenishment
  end

  test "shows store platform stockout events on the main timeline" do
    first = create_event("first_sale", Time.zone.parse("2026-01-01"), first_sale_content)
    stockout = create_event("platform_stockout", Time.zone.parse("2026-02-01"), {
      platform: "ozon", quantity: 0, first_zero_date: "2026-02-01",
      confirmed_on: "2026-02-03", consecutive_zero_days: 3, time_precision: "date"
    })
    query = Ec::SkuLifecycleQuery.new(@sku, user_today: Date.new(2026, 8, 1),
      time_zone: Time.find_zone!("Asia/Shanghai"))

    nodes = query.send(:timeline_nodes, @sku.lifecycle_events.chronological.to_a, first)

    assert_includes nodes.filter_map { |node| node[:event] }, stockout
  end

  test "shows store platform recovery events on the main timeline" do
    first = create_event("first_sale", Time.zone.parse("2026-01-01"), first_sale_content)
    recovery = create_event("stock_recovered", Time.zone.parse("2026-02-05"), {
      scope: "platform_store", stockout_source_key: "platform_stockout:test",
      recovered_on: "2026-02-05", confirmed_on: "2026-02-06", platform_stock: 5,
      confirmation_days: 2, time_precision: "date", platform: "ozon", store_id: 3,
      store_name: "Test store", quantity: 5
    })
    query = Ec::SkuLifecycleQuery.new(@sku, user_today: Date.new(2026, 8, 1),
      time_zone: Time.find_zone!("Asia/Shanghai"))

    nodes = query.send(:timeline_nodes, @sku.lifecycle_events.chronological.to_a, first)

    assert_includes nodes.filter_map { |node| node[:event] }, recovery
  end

  private

  def create_event(type, time, content)
    @sku.lifecycle_events.create!(event_type: type, occurred_at: time,
      source_key: "#{type}:#{SecureRandom.hex(6)}", content: content)
  end

  def first_sale_content
    { order_id: 1, order_item_id: 1, platform: "ozon", store_id: 1,
      sku_product_id: 1, quantity: 1, platform_sku_id: "1" }
  end
end
