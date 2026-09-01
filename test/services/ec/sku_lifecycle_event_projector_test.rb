require "test_helper"

class Ec::SkuLifecycleEventProjectorTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(5).upcase
    @sku = Ec::Sku.create!(sku_code: "LIFECYCLE-PROJECT-#{@token}")
  end

  teardown do
    Ec::SkuLifecycleEvent.where(sku_id: @sku.id).delete_all
    Ec::Snapshot.where(sku_id: @sku.id).delete_all
    Ec::SkuMarketingState.where(sku_id: @sku.id).delete_all
    Ec::SkuBatch.where(sku_code: @sku.sku_code).delete_all
    Ec::OrderItem.where(store_id: @store&.id).delete_all
    Ec::Order.where(store_id: @store&.id).delete_all
    Ec::SkuProduct.where(sku_code: @sku.sku_code).delete_all
    Ec::Store.where(id: @store&.id).delete_all
    Ec::Sku.with_deleted.where(id: @sku.id).delete_all
  end

  test "projects marketing and purchase facts idempotently using authoritative dates" do
    first = @sku.marketing_states.create!(grade: "B", stage: "new",
      effective_at: Time.zone.parse("2026-07-01 10:00"), ended_at: Time.zone.parse("2026-07-05 10:00"))
    second = @sku.marketing_states.create!(grade: "A", stage: "grw", effective_at: Time.zone.parse("2026-07-05 10:00"))
    batch = @sku.batches.create!(batch_code: "BATCH-#{@token}", batch_type: :normal, status: "received",
      purchase_date: Date.new(2026, 7, 2), purchased_quantity: 20,
      received_on: Date.new(2026, 7, 8), received_quantity: 18, purchase_unit_price_cny: 3)

    Ec::SkuLifecycleEventProjector.run(sku_ids: [ @sku.id ])
    original_created_at = @sku.lifecycle_events.minimum(:created_at)
    travel 1.minute do
      Ec::SkuLifecycleEventProjector.run(sku_ids: [ @sku.id ])
    end

    assert_equal 4, @sku.lifecycle_events.count
    assert_equal original_created_at, @sku.lifecycle_events.minimum(:created_at)
    first_event = @sku.lifecycle_events.find_by!(source_key: "marketing_state:#{first.id}")
    second_event = @sku.lifecycle_events.find_by!(source_key: "marketing_state:#{second.id}")
    assert_equal true, first_event.content["initial_state"]
    assert_equal "B", second_event.content["from_grade"]
    assert_equal "2026-07-02", @sku.lifecycle_events.find_by!(source_key: "purchase_ordered:sku_batch:#{batch.id}").occurred_at.in_time_zone("Asia/Shanghai").to_date.iso8601
    assert_equal 18, @sku.lifecycle_events.find_by!(source_key: "purchase_received:sku_batch:#{batch.id}").content["received_quantity"]
  end

  test "corrects first sale when earlier orders arrive or the source becomes invalid" do
    create_store_binding
    later = create_order("LATER", Time.zone.parse("2026-07-10 10:00"), "delivered")
    Ec::SkuLifecycleEventProjector.run(sku_ids: [ @sku.id ])
    event = @sku.lifecycle_events.find_by!(event_type: "first_sale")
    assert_equal later.id, event.source_id

    earlier = create_order("EARLIER", Time.zone.parse("2026-07-01 10:00"), "processing")
    Ec::SkuLifecycleEventProjector.run(sku_ids: [ @sku.id ])
    event.reload
    assert_equal earlier.id, event.source_id
    assert_equal 1, @sku.lifecycle_events.where(event_type: "first_sale").count

    earlier.update!(order_status: "cancelled")
    Ec::SkuLifecycleEventProjector.run(sku_ids: [ @sku.id ])
    assert_equal later.id, event.reload.source_id

    later.update!(order_status: "returned")
    Ec::SkuLifecycleEventProjector.run(sku_ids: [ @sku.id ])
    assert_not @sku.lifecycle_events.exists?(event_type: "first_sale")
  end

  test "does not project purchase facts when authoritative business dates are missing" do
    batch = @sku.batches.create!(batch_code: "BATCH-NODATE-#{@token}", batch_type: :normal,
      status: "ordered", purchased_quantity: 20, purchase_unit_price_cny: 3)

    result = Ec::SkuLifecycleEventProjector.run(sku_ids: [ @sku.id ])

    assert_not @sku.lifecycle_events.exists?(source_key: "purchase_ordered:sku_batch:#{batch.id}")
    assert_equal "missing_purchase_date", result[:warnings].find { |item| item[:source_id] == batch.id }[:reason]
  end

  test "confirms stockout and recovery from consecutive valid observations" do
    create_store_binding
    create_snapshot(Date.new(2026, 7, 1), 5)
    (2..4).each { |day| create_snapshot(Date.new(2026, 7, day), 0) }
    create_snapshot(Date.new(2026, 7, 5), 1)
    create_snapshot(Date.new(2026, 7, 6), 3)
    create_snapshot(Date.new(2026, 7, 7), 4)

    2.times { Ec::SkuLifecycleEventProjector.run(sku_ids: [ @sku.id ]) }

    stockout = @sku.lifecycle_events.find_by!(event_type: "all_platform_stockout")
    recovery = @sku.lifecycle_events.where(event_type: "stock_recovered").find { |event| event.source_key.include?("all_platform") }
    assert_equal Date.new(2026, 7, 2), stockout.occurred_at.in_time_zone("Asia/Shanghai").to_date
    assert_equal "2026-07-04", stockout.content["confirmed_on"]
    assert_equal Date.new(2026, 7, 6), recovery.occurred_at.in_time_zone("Asia/Shanghai").to_date
    assert_equal stockout.source_key, recovery.content["stockout_source_key"]
    assert_equal 1, @sku.lifecycle_events.where(event_type: "all_platform_stockout").count
  end

  private

  def create_store_binding
    @store = Ec::Store.create!(platform: "ozon", store_name: "Lifecycle #{@token}", company_type: "general",
      ozon_raw_account_id: 800_000_000 + rand(10_000_000))
    Ec::SkuProduct.create!(sku: @sku, store: @store, product_id: "P-#{@token}", platform_sku_id: "PS-#{@token}")
  end

  def create_snapshot(date, quantity)
    synced_at = Time.find_zone!("Asia/Shanghai").local(date.year, date.month, date.day, 12)
    Ec::Snapshot.create!(sku: @sku, snapshot_type: "inventory", snapshot_date: date, content: {
      overview: { daily_sales_velocity: "1.0" },
      distribution: { levels: [ { platform: "ozon", store_id: @store.id, account_id: @store.ozon_raw_account_id,
        store_name: @store.store_name, fulfillment_type: "fbo", quantity:, synced_at: synced_at.iso8601 } ] }
    })
  end

  def create_order(suffix, ordered_at, status)
    order = Ec::Order.create!(platform: "ozon", store: @store, order_key: "lifecycle:#{@token}:#{suffix}",
      order_status: status, ordered_at:, synced_at: ordered_at)
    order.items.create!(platform: "ozon", store: @store, external_item_id: "#{@token}-#{suffix}",
      platform_sku_id: "PS-#{@token}", sku_code: nil, quantity: 2, synced_at: ordered_at)
    order
  end
end
