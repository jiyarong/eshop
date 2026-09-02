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

  test "projects A and later S from the first single qualifying complete week" do
    weeks = [ Date.new(2026, 7, 6)..Date.new(2026, 7, 12), Date.new(2026, 7, 13)..Date.new(2026, 7, 19) ]
    reports = [
      profit_report(annualized_profit: 100_000, annualized_return: 80.01, after_tax: 2_000),
      profit_report(annualized_profit: 250_000.01, annualized_return: 100.01, after_tax: 5_000)
    ]
    projector = Ec::SkuLifecycleEventProjector.new(sku_ids: [ @sku.id ])
    projector.define_singleton_method(:milestone_weeks) { weeks }

    with_weekly_reports(->(**) { reports.shift }) do
      projector.send(:project_profit_grade_milestones)
    end

    events = @sku.lifecycle_events.where(event_type: "profit_grade_reached").chronological.to_a
    assert_equal %w[A S], events.map { |event| event.content["grade"] }
    assert_equal %w[2026-07-12 2026-07-19], events.map { |event| event.content["week_to"] }
  end

  test "projects only S when the first qualifying week reaches S" do
    week = Date.new(2026, 7, 6)..Date.new(2026, 7, 12)
    projector = Ec::SkuLifecycleEventProjector.new(sku_ids: [ @sku.id ])
    projector.define_singleton_method(:milestone_weeks) { [ week ] }

    report = profit_report(annualized_profit: 300_000, annualized_return: 120, after_tax: 6_000)
    with_weekly_reports(->(**) { report }) do
      projector.send(:project_profit_grade_milestones)
    end

    assert_equal [ "S" ], @sku.lifecycle_events.where(event_type: "profit_grade_reached")
      .pluck(:content).map { |content| content["grade"] }
  end

  test "uses strict annualized return boundaries without multi-week confirmation" do
    projector = Ec::SkuLifecycleEventProjector.new(sku_ids: [ @sku.id ])

    assert_nil projector.send(:profit_candidate_grade, profit_row(250_000, 80))
    assert_equal "A", projector.send(:profit_candidate_grade, profit_row(250_000, 100))
    assert_nil projector.send(:profit_candidate_grade, profit_row(nil, 120))
    assert_equal "S", projector.send(:profit_candidate_grade, profit_row(250_000.01, 100.01))
  end

  test "projects cumulative profit milestones on the first crossing week" do
    weeks = [ Date.new(2026, 7, 6)..Date.new(2026, 7, 12), Date.new(2026, 7, 13)..Date.new(2026, 7, 19) ]
    reports = [
      profit_report(annualized_profit: nil, annualized_return: nil, after_tax: 90_000),
      profit_report(annualized_profit: nil, annualized_return: nil, after_tax: 920_000)
    ]
    cumulative_reports = [
      profit_report(annualized_profit: nil, annualized_return: nil, after_tax: 90_000),
      profit_report(annualized_profit: nil, annualized_return: nil, after_tax: 1_010_000)
    ]
    projector = Ec::SkuLifecycleEventProjector.new(sku_ids: [ @sku.id ])
    projector.define_singleton_method(:milestone_weeks) { weeks }
    projector.define_singleton_method(:cumulative_profit_groups) { |_sku_codes| {} }
    projector.define_singleton_method(:cumulative_profit_rows) { |_week, _groups| cumulative_reports.shift.fetch(:rows) }

    with_weekly_reports(->(**) { reports.shift }) do
      projector.send(:project_profit_grade_milestones)
    end

    events = @sku.lifecycle_events.where(event_type: "cumulative_profit_reached").chronological.to_a
    assert_equal [ 100_000, 250_000, 1_000_000 ], events.map { |event| event.content["threshold_cny"] }
    assert events.all? { |event| event.content["week_to"] == "2026-07-19" }
    assert_equal [ "1010000.0" ], events.map { |event| event.content["cumulative_profit_cny"] }.uniq
  end

  test "uses lifecycle-to-week profit for incremental projection" do
    week = Date.new(2026, 7, 13)..Date.new(2026, 7, 19)
    weekly = profit_report(annualized_profit: nil, annualized_return: nil, after_tax: 10_000)
    cumulative = profit_report(annualized_profit: nil, annualized_return: nil, after_tax: 105_000)
    calls = []
    projector = Ec::SkuLifecycleEventProjector.new(
      sku_ids: [ @sku.id ], from_date: week.begin, to_date: week.end
    )
    sku_code = @sku.sku_code
    projector.define_singleton_method(:milestone_weeks) { [ week ] }
    projector.define_singleton_method(:cumulative_profit_groups) do |_sku_codes|
      { Date.new(2026, 7, 1).beginning_of_week(:monday) => [ sku_code ] }
    end

    with_weekly_reports(->(**args) { calls << args; calls.size == 1 ? weekly : cumulative }) do
      projector.send(:project_profit_grade_milestones)
    end

    event = @sku.lifecycle_events.find_by!(event_type: "cumulative_profit_reached")
    assert_equal 100_000, event.content["threshold_cny"]
    assert_equal "105000.0", event.content["cumulative_profit_cny"]
    assert_equal Date.new(2026, 7, 1).beginning_of_week(:monday), calls.second[:from_date]
    assert_equal week.end, calls.second[:to_date]
  end

  test "confirms stockout and recovery from consecutive valid observations" do
    create_store_binding
    create_order("FIRST", Time.zone.parse("2026-06-30 10:00"), "delivered")
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

  test "does not treat pre-sale zero inventory as stockout or recovery" do
    create_store_binding
    (26..28).each { |day| create_snapshot(Date.new(2026, 6, day), 0) }
    create_order("FIRST", Time.zone.parse("2026-08-05 13:40"), "delivered")
    create_snapshot(Date.new(2026, 8, 5), 0)
    create_snapshot(Date.new(2026, 8, 6), 4)
    create_snapshot(Date.new(2026, 8, 7), 4)

    Ec::SkuLifecycleEventProjector.run(sku_ids: [ @sku.id ])

    assert_not @sku.lifecycle_events.exists?(event_type: %w[platform_stockout all_platform_stockout stock_recovered])
  end

  test "requires positive saleable stock after first sale before confirming all-platform stockout" do
    create_store_binding
    create_order("FIRST", Time.zone.parse("2026-07-01 10:00"), "delivered")
    (1..4).each { |day| create_snapshot(Date.new(2026, 7, day), 0) }

    Ec::SkuLifecycleEventProjector.run(sku_ids: [ @sku.id ])

    assert_not @sku.lifecycle_events.exists?(event_type: "all_platform_stockout")
  end

  private

  def with_weekly_reports(replacement)
    original = Ec::WeeklySummaryDeepQuery.method(:run)
    Ec::WeeklySummaryDeepQuery.define_singleton_method(:run, replacement)
    yield
  ensure
    Ec::WeeklySummaryDeepQuery.define_singleton_method(:run, original)
  end

  def profit_report(annualized_profit:, annualized_return:, after_tax:)
    { rows: [ profit_row(annualized_profit, annualized_return).merge(after_tax:) ] }
  end

  def profit_row(annualized_profit, annualized_return)
    { sku: @sku.sku_code, annualized_net_profit_cny: annualized_profit,
      annualized_return_pct: annualized_return }
  end

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
