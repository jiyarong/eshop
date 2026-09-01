require "test_helper"

class Ec::SkuLifecycleQueryTest < ActiveSupport::TestCase
  setup do
    @sku = Ec::Sku.create!(sku_code: "LIFECYCLE-QUERY-#{SecureRandom.hex(6)}")
  end

  teardown do
    Ec::SkuLifecycleEvent.where(sku_id: @sku.id).delete_all
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
