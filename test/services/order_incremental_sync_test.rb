require "test_helper"
require "securerandom"

class OrderIncrementalSyncTest < ActiveSupport::TestCase
  class FakeWbClient
    def initialize(response)
      @response = response
    end

    def get(*)
      @response
    end
  end

  class FakeOzonClient
    def initialize(response)
      @response = response
    end

    def post(*)
      @response
    end
  end

  test "wb incremental sync declares only order steps" do
    assert_equal %i[
      sync_new_orders
      sync_orders
      sync_stats_orders
    ], RawWb::OrderIncrementalSync::STEPS
  end

  test "ozon incremental sync declares only posting steps" do
    assert_equal %i[
      sync_postings_fbs
      sync_postings_fbo
    ], RawOzon::OrderIncrementalSync::STEPS
  end

  test "wb daily sync uses the platform sync lock and waits" do
    calls = []

    with_singleton_method(SyncRunLock, :with_lock, ->(name, wait:, logger:) {
      calls << [name, wait, logger]
      :locked
    }) do
      assert_equal :locked, RawWb::DailySync.run
    end

    assert_equal [["raw_wb:daily_sync", true, Rails.logger]], calls
  end

  test "ozon daily sync uses the platform sync lock and waits" do
    calls = []

    with_singleton_method(SyncRunLock, :with_lock, ->(name, wait:, logger:) {
      calls << [name, wait, logger]
      :locked
    }) do
      assert_equal :locked, RawOzon::DailySync.run
    end

    assert_equal [["raw_ozon:daily_sync", true, Rails.logger]], calls
  end

  test "wb incremental sync skips automatically when the lock is busy" do
    called = false
    release_lock = Queue.new
    lock_ready = Queue.new

    holder = Thread.new do
      with_singleton_method(RawWb::OrderIncrementalSync, :new, ->(*) {
        called = true
        raise "incremental sync should not start while lock is busy"
      }) do
        SyncRunLock.with_lock("raw_wb:daily_sync", wait: true, logger: Rails.logger) do
          lock_ready << true
          release_lock.pop
        end
      end
    end

    lock_ready.pop
    begin
      with_singleton_method(RawWb::OrderIncrementalSync, :new, ->(*) {
        called = true
        raise "incremental sync should not start while lock is busy"
      }) do
        result = RawWb::OrderIncrementalSync.run

        assert_equal({ skipped: true, reason: "lock_busy" }, result)
      end
    ensure
      release_lock << true
      holder.join
    end

    assert_equal false, called
  end

  test "wb incremental sync imports normalized wb orders after raw sync" do
    token = SecureRandom.hex(6)
    account = RawWb::SellerAccount.create!(
      name: "wb-inc-#{token}",
      api_token: "token-#{token}",
      company_type: "small"
    )
    store = Ec::Store.create!(
      platform: "wb",
      store_name: "wb-inc-store-#{token}",
      company_type: "small",
      wb_raw_account_id: account.id,
      is_active: true
    )
    imported = false

    with_singleton_method(RawWb::OrderIncrementalSync, :new, ->(*) {
      Object.new.tap do |runner|
        runner.define_singleton_method(:run) { |sync_keys: nil| { sync_orders: { ok: 0 } } }
      end
    }) do
      with_singleton_method(Ec::OrderImport::Wb, :new, -> {
        Object.new.tap { |importer| importer.define_singleton_method(:call) { imported = true } }
      }) do
        RawWb::OrderIncrementalSync.run
      end
    end

    assert_equal true, imported
  ensure
    Ec::Store.where(id: store&.id).delete_all
    RawWb::SellerAccount.where(id: account&.id).delete_all
  end

  test "wb new orders returns fetched created and updated counts" do
    token = SecureRandom.hex(6)
    account = RawWb::SellerAccount.create!(
      name: "wb-counts-#{token}",
      api_token: "token-#{token}",
      company_type: "small"
    )
    RawWb::Order.create!(
      account: account,
      wb_order_id: 1_001,
      delivery_type: "fbs",
      supplier_status: "new",
      wb_status: "waiting",
      created_at: Time.zone.parse("2026-06-01 10:00:00"),
      updated_at: Time.zone.parse("2026-06-01 10:00:00")
    )
    sync = RawWb::OrderIncrementalSync.new(account, days: 2)
    sync.instance_variable_set(:@client, FakeWbClient.new("orders" => [
      wb_order_payload(1_001),
      wb_order_payload(1_002)
    ]))

    result = sync.sync_new_orders

    assert_equal({ ok: 2, fetched: 2, created: 1, updated: 1 }, result)
  ensure
    RawWb::Order.where(account_id: account&.id).delete_all
    RawWb::SellerAccount.where(id: account&.id).delete_all
  end

  test "ozon incremental sync skips automatically when the lock is busy" do
    called = false
    release_lock = Queue.new
    lock_ready = Queue.new

    holder = Thread.new do
      with_singleton_method(RawOzon::OrderIncrementalSync, :new, ->(*) {
        called = true
        raise "incremental sync should not start while lock is busy"
      }) do
        SyncRunLock.with_lock("raw_ozon:daily_sync", wait: true, logger: Rails.logger) do
          lock_ready << true
          release_lock.pop
        end
      end
    end

    lock_ready.pop
    begin
      with_singleton_method(RawOzon::OrderIncrementalSync, :new, ->(*) {
        called = true
        raise "incremental sync should not start while lock is busy"
      }) do
        result = RawOzon::OrderIncrementalSync.run

        assert_equal({ skipped: true, reason: "lock_busy" }, result)
      end
    ensure
      release_lock << true
      holder.join
    end

    assert_equal false, called
  end

  test "ozon incremental sync imports normalized ozon orders after raw sync" do
    token = SecureRandom.hex(6)
    account = RawOzon::SellerAccount.create!(
      client_id: "ozon-inc-#{token}",
      api_key: "token-#{token}",
      company_type: "general",
      raw_json: {}
    )
    store = Ec::Store.create!(
      platform: "ozon",
      store_name: "ozon-inc-store-#{token}",
      company_type: "general",
      ozon_raw_account_id: account.id,
      ozon_client_id: "ozon-store-#{token}",
      is_active: true
    )
    imported = false

    with_singleton_method(RawOzon::OrderIncrementalSync, :new, ->(*) {
      Object.new.tap do |runner|
        runner.define_singleton_method(:run) { |sync_keys: nil| { sync_postings_fbs: { ok: 0 } } }
      end
    }) do
      with_singleton_method(Ec::OrderImport::Ozon, :new, -> {
        Object.new.tap { |importer| importer.define_singleton_method(:call) { imported = true } }
      }) do
        RawOzon::OrderIncrementalSync.run
      end
    end

    assert_equal true, imported
  ensure
    Ec::Store.where(id: store&.id).delete_all
    RawOzon::SellerAccount.where(id: account&.id).delete_all
  end

  test "ozon fbo postings returns fetched created and updated counts" do
    token = SecureRandom.hex(6)
    account = RawOzon::SellerAccount.create!(
      client_id: "ozon-counts-#{token}",
      api_key: "token-#{token}",
      company_type: "general",
      raw_json: {}
    )
    RawOzon::PostingFbo.create!(
      account: account,
      posting_number: "FBO-COUNT-1-#{token}",
      order_id: 1_001,
      order_number: "ORDER-1-#{token}",
      status: "delivered",
      raw_json: {},
      created_at: Time.zone.parse("2026-06-01 10:00:00")
    )
    sync = RawOzon::OrderIncrementalSync.new(account, days: 2)
    sync.instance_variable_set(:@client, FakeOzonClient.new("result" => [
      ozon_fbo_payload("FBO-COUNT-1-#{token}"),
      ozon_fbo_payload("FBO-COUNT-2-#{token}")
    ]))

    result = sync.sync_postings_fbo

    assert_equal({ ok: 2, fetched: 2, created: 1, updated: 1 }, result)
  ensure
    RawOzon::PostingItem.where(account_id: account&.id).delete_all
    RawOzon::PostingFbo.where(account_id: account&.id).delete_all
    RawOzon::SellerAccount.where(id: account&.id).delete_all
  end

  test "wb base sync logs fetched created and updated counts for structured step results" do
    token = SecureRandom.hex(6)
    account = RawWb::SellerAccount.create!(
      name: "wb-log-#{token}",
      api_token: "token-#{token}",
      company_type: "small"
    )
    sync = RawWb::OrderIncrementalSync.new(account, days: 2)
    logger = CapturingLogger.new

    with_singleton_method(sync, :sync_new_orders, -> { { ok: 2, fetched: 2, created: 1, updated: 1 } }) do
      with_constant_logger(logger) do
        sync.run(sync_keys: [:sync_new_orders])
      end
    end

    assert_includes logger.messages.join("\n"), "sync_new_orders: fetched=2, created=1, updated=1, records=2"
  ensure
    RawWb::SellerAccount.where(id: account&.id).delete_all
  end

  private

  class CapturingLogger
    attr_reader :messages

    def initialize
      @messages = []
    end

    def info(message)
      @messages << message
    end

    def warn(message)
      @messages << message
    end

    def error(message)
      @messages << message
    end
  end

  def with_singleton_method(klass, method_name, replacement)
    original = klass.method(method_name)
    klass.define_singleton_method(method_name, replacement)
    yield
  ensure
    klass.define_singleton_method(method_name, original)
  end

  def with_constant_logger(logger)
    with_singleton_method(Rails, :logger, -> { logger }) { yield }
  end

  def wb_order_payload(id)
    {
      "id" => id,
      "orderUid" => "uid-#{id}",
      "rid" => "rid-#{id}",
      "deliveryType" => "fbs",
      "nmId" => id,
      "article" => "SKU#{id}",
      "skus" => ["BAR#{id}"],
      "supplierStatus" => "new",
      "wbStatus" => "waiting",
      "price" => 10_000,
      "convertedPrice" => 10_000,
      "currencyCode" => 643,
      "createdAt" => Time.zone.parse("2026-06-10 10:00:00")
    }
  end

  def ozon_fbo_payload(posting_number)
    {
      "posting_number" => posting_number,
      "order_id" => 1_002,
      "order_number" => "ORDER-#{posting_number}",
      "status" => "delivered",
      "substatus" => "posting_received",
      "products" => [],
      "financial_data" => {},
      "analytics_data" => {},
      "created_at" => Time.zone.parse("2026-06-10 10:00:00")
    }
  end
end
