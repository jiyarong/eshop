require "test_helper"
require_relative "../../../support/book_ledger_fixtures"

class Ec::FulfillmentBusinessStatus::BackfillTest < ActiveSupport::TestCase
  include BookLedgerFixtures

  setup { setup_ledger_world }
  teardown { teardown_ledger_world }

  def scoped_run(**options)
    Ec::FulfillmentBusinessStatus::Backfill.run(
      store_ids: [ @wb_store.id, @ozon_store.id ], **options
    )
  end

  test "dry run reports differences without writing" do
    order = ledger_order(platform: "ozon", status: "delivered", source_status: "delivered",
      source_substatus: "posting_received")

    result = scoped_run(dry_run: true)

    assert_equal 1, result[:checked]
    assert_equal 1, result[:changed]
    assert_equal [ "needs_review", "none" ], result[:samples].first[:from]
    assert_equal [ "delivered", "none" ], result[:samples].first[:to]
    assert_equal "needs_review", order.fulfillments.first.reload.business_status
    assert_equal "needs_review", order.reload.business_status
  end

  test "backfill writes statuses and is idempotent" do
    order = ledger_order(platform: "wb", status: "delivered", source_status: "sold", source_substatus: "complete")
    ledger_order(platform: "ozon", status: "processing", source_status: "awaiting_packaging",
      source_substatus: "posting_created")

    first = scoped_run
    second = scoped_run

    assert_equal 2, first[:changed]
    assert_equal 0, second[:changed]
    assert_equal "delivered", order.fulfillments.first.reload.business_status
    assert_equal "delivered", order.reload.business_status
  end

  test "reclassifies a delivered fulfillment that has a return as returned" do
    order = ledger_order(platform: "ozon", status: "delivered", source_status: "delivered",
      source_substatus: "posting_received")
    ledger_return(order, source_status: "ReceivedBySeller")
    order.fulfillments.first.update_columns(business_status: "delivered", return_business_status: "received_by_seller")
    order.update_columns(business_status: "delivered", return_business_status: "received_by_seller")

    dry = scoped_run(dry_run: true)

    assert_equal 1, dry[:changed]
    assert_equal [ "delivered", "received_by_seller" ], dry[:samples].first[:from]
    assert_equal [ "returned", "received_by_seller" ], dry[:samples].first[:to]
    assert_equal "delivered", order.fulfillments.first.reload.business_status

    first = scoped_run
    second = scoped_run

    assert_equal 1, first[:changed]
    assert_equal 0, second[:changed]
    assert_equal "returned", order.fulfillments.first.reload.business_status
    assert_equal "returned", order.reload.business_status
  end

  test "repairs a stale order summary whose fulfillments already match, and a dry run leaves it alone" do
    order = ledger_order(platform: "ozon", status: "delivered", source_status: "delivered",
      source_substatus: "posting_received")
    order.fulfillments.first.update_columns(business_status: "delivered", return_business_status: "none")
    order.update_columns(business_status: "needs_review", return_business_status: "none")

    dry = scoped_run(dry_run: true)

    assert_equal 0, dry[:changed]
    assert_equal "needs_review", order.reload.business_status

    result = scoped_run

    assert_equal 0, result[:changed]
    assert_equal "delivered", order.reload.business_status
  end

  def stale_ozon_order
    order = ledger_order(platform: "ozon", status: "delivered", source_status: "delivered",
      source_substatus: "posting_received")
    order.fulfillments.first.update_columns(business_status: "needs_review", return_business_status: "none")
    order
  end

  def with_singleton_override(target, name, replacement)
    original = target.method(name)
    target.define_singleton_method(name, &replacement)
    yield
  ensure
    target.define_singleton_method(name, original)
  end

  def severity_logger(io)
    ActiveSupport::Logger.new(io).tap do |logger|
      logger.formatter = proc { |severity, _time, _progname, message| "#{severity} #{message}\n" }
    end
  end

  def lock_held_elsewhere?(name)
    connection = ActiveRecord::Base.connection_pool.checkout
    key = SyncRunLock.lock_key(name)
    # uncached: an enabled query cache would replay the first (false) answer for the identical statement.
    acquired = connection.uncached { connection.select_value("SELECT pg_try_advisory_lock(#{key.to_i})") }
    connection.uncached { connection.select_value("SELECT pg_advisory_unlock(#{key.to_i})") } if acquired
    !acquired
  ensure
    ActiveRecord::Base.connection_pool.checkin(connection) if connection
  end

  test "run_scheduled repairs stale fulfillments and returns the counts" do
    order = stale_ozon_order
    log = StringIO.new

    result = Ec::FulfillmentBusinessStatus::Backfill.run_scheduled(
      logger: ActiveSupport::Logger.new(log), store_ids: [ @wb_store.id, @ozon_store.id ]
    )

    assert_equal 1, result[:checked]
    assert_equal 1, result[:changed]
    assert_equal "delivered", order.fulfillments.first.reload.business_status
    assert_equal "delivered", order.reload.business_status
  end

  test "run_scheduled holds both sync locks, WB then Ozon, only while the backfill runs" do
    wb_name = RawWb::OrderIncrementalSync::LOCK_NAME
    ozon_name = RawOzon::OrderIncrementalSync::LOCK_NAME
    calls = []
    held_during_run = nil
    original = SyncRunLock.method(:with_lock)

    spy = proc do |name, wait:, logger: Rails.logger, &block|
      calls << [ name, wait ]
      original.call(name, wait: wait, logger: logger, &block)
    end
    held_check = method(:lock_held_elsewhere?)
    fake_run = proc do |**_options|
      held_during_run = [ held_check.call(wb_name), held_check.call(ozon_name) ]
      { checked: 0, changed: 0, samples: [] }
    end

    assert_not lock_held_elsewhere?(wb_name)
    assert_not lock_held_elsewhere?(ozon_name)

    with_singleton_override(SyncRunLock, :with_lock, spy) do
      with_singleton_override(Ec::FulfillmentBusinessStatus::Backfill, :run, fake_run) do
        Ec::FulfillmentBusinessStatus::Backfill.run_scheduled(logger: ActiveSupport::Logger.new(StringIO.new))
      end
    end

    assert_equal [ [ "raw_wb:daily_sync", true ], [ "raw_ozon:daily_sync", true ] ], calls
    assert_equal [ true, true ], held_during_run
    assert_not lock_held_elsewhere?(wb_name)
    assert_not lock_held_elsewhere?(ozon_name)
  end

  test "run_scheduled logs a warning with samples only when it repaired something" do
    quiet = StringIO.new
    Ec::FulfillmentBusinessStatus::Backfill.run_scheduled(
      logger: severity_logger(quiet), store_ids: [ @wb_store.id, @ozon_store.id ]
    )

    assert_match(/INFO \[FulfillmentBusinessStatus\] scheduled backfill checked=0 changed=0/, quiet.string)
    assert_no_match(/WARN/, quiet.string)

    stale = stale_ozon_order
    noisy = StringIO.new
    Ec::FulfillmentBusinessStatus::Backfill.run_scheduled(
      logger: severity_logger(noisy), store_ids: [ @wb_store.id, @ozon_store.id ]
    )

    assert_match(/scheduled backfill checked=1 changed=1/, noisy.string)
    assert_match(/WARN.*\[FulfillmentBusinessStatus\] scheduled backfill repaired 1 stale fulfillment\(s\)/, noisy.string)
    assert_includes noisy.string, stale.fulfillments.first.id.to_s
  end

  test "recurring.yml schedules the backfill daily in production" do
    entry = YAML.safe_load_file(Rails.root.join("config/recurring.yml")).fetch("production")
      .fetch("fulfillment_business_status_backfill")

    assert_equal "Ec::FulfillmentBusinessStatus::Backfill.run_scheduled", entry["command"]
    assert_equal "every day at 4:10 in Asia/Shanghai", entry["schedule"]
  end
end
