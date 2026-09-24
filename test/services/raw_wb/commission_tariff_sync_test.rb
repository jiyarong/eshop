require "test_helper"
require "securerandom"

class RawWb::CommissionTariffSyncTest < ActiveSupport::TestCase
  class FakeWbClient
    attr_reader :calls

    def initialize(response: nil, error: nil)
      @response = response
      @error = error
      @calls = 0
    end

    def get(*args, **kwargs)
      @calls += 1
      raise @error if @error
      @response
    end
  end

  def official_report_payload
    {
      "report" => [
        {
          "kgvpMarketplace" => 21,
          "paidStorageKgvp" => 17.5,
          "kgvpSupplier" => 20,
          "kgvpPickup" => 15.5,
          "kgvpBooking" => 15.5,
          "kgvpSupplierExpress" => 3,
          "parentID" => 739,
          "parentName" => "Категория",
          "subjectID" => 3319,
          "subjectName" => "Предмет"
        },
        {
          "kgvpMarketplace" => 18,
          "paidStorageKgvp" => 12.25,
          "kgvpSupplier" => nil,
          "kgvpPickup" => nil,
          "kgvpBooking" => nil,
          "kgvpSupplierExpress" => nil,
          "parentID" => 740,
          "parentName" => "Категория 2",
          "subjectID" => 4001,
          "subjectName" => "Предмет 2"
        }
      ],
      "requestId" => "req-123"
    }
  end

  def create_account(suffix)
    RawWb::SellerAccount.create!(
      name: "wb-commission-sync-#{suffix}-#{SecureRandom.hex(4)}",
      api_token: "token-#{SecureRandom.hex(6)}",
      company_type: "small",
      is_active: true
    )
  end

  def cleanup_account(account)
    return unless account
    RawWb::CommissionTariff.where(
      snapshot_id: RawWb::CommissionTariffSnapshot.where(source_account_id: account.id).select(:id)
    ).delete_all
    RawWb::CommissionTariffSnapshot.where(source_account_id: account.id).delete_all
    RawWb::SellerAccount.where(id: account.id).delete_all
  end

  test "syncs the official report shape and promotes the new snapshot to current" do
    account = create_account("primary")
    client = FakeWbClient.new(response: official_report_payload)

    begin
      result = RawWb::CommissionTariffSync.new(
        account_scope: RawWb::SellerAccount.where(id: account.id),
        client_factory: ->(_) { client }
      ).run

      snapshot = RawWb::CommissionTariffSnapshot.find(result[:snapshot_id])
      assert_equal "succeeded", snapshot.status
      assert snapshot.is_current
      assert_equal 2, snapshot.item_count
      assert_equal "req-123", snapshot.request_id
      assert_equal account.id, snapshot.source_account_id

      tariff = RawWb::CommissionTariff.find_by!(snapshot_id: snapshot.id, wb_subject_id: 3319)
      assert_equal 739, tariff.wb_parent_id
      assert_equal "Категория", tariff.parent_name
      assert_equal "Предмет", tariff.subject_name
      assert_equal BigDecimal("15.5"), tariff.kgvp_booking
      assert_equal BigDecimal("21"), tariff.kgvp_marketplace
      assert_equal BigDecimal("15.5"), tariff.kgvp_pickup
      assert_equal BigDecimal("20"), tariff.kgvp_supplier
      assert_equal BigDecimal("3"), tariff.kgvp_supplier_express
      assert_equal BigDecimal("17.5"), tariff.paid_storage_kgvp

      untouched = RawWb::CommissionTariff.find_by!(snapshot_id: snapshot.id, wb_subject_id: 4001)
      assert_nil untouched.kgvp_supplier
      assert_nil untouched.kgvp_pickup
    ensure
      cleanup_account(account)
    end
  end

  test "keeps the previous current snapshot when the response is missing subjectID" do
    account = create_account("invalid")
    good_client = FakeWbClient.new(response: official_report_payload)
    previous = RawWb::CommissionTariffSync.new(
      account_scope: RawWb::SellerAccount.where(id: account.id),
      client_factory: ->(_) { good_client }
    ).run
    previous_snapshot = RawWb::CommissionTariffSnapshot.find(previous[:snapshot_id])

    bad_payload = { "report" => [ { "parentID" => 1, "parentName" => "x", "subjectName" => "y", "kgvpMarketplace" => 10 } ] }
    bad_client = FakeWbClient.new(response: bad_payload)

    begin
      assert_raises(RawWb::CommissionTariffSync::InvalidResponseError) do
        RawWb::CommissionTariffSync.new(
          account_scope: RawWb::SellerAccount.where(id: account.id),
          client_factory: ->(_) { bad_client }
        ).run
      end

      assert previous_snapshot.reload.is_current
      failed_snapshot = RawWb::CommissionTariffSnapshot.where(source_account_id: account.id, status: "failed").sole
      assert_equal 0, RawWb::CommissionTariff.where(snapshot_id: failed_snapshot.id).count
    ensure
      cleanup_account(account)
    end
  end

  test "keeps the previous current snapshot when the WB API raises a retryable error" do
    account = create_account("retryable-failure")
    good_client = FakeWbClient.new(response: official_report_payload)
    previous = RawWb::CommissionTariffSync.new(
      account_scope: RawWb::SellerAccount.where(id: account.id),
      client_factory: ->(_) { good_client }
    ).run
    previous_snapshot = RawWb::CommissionTariffSnapshot.find(previous[:snapshot_id])

    failing_client = FakeWbClient.new(error: RawWb::WbClient::RetryableError.new("429 rate-limited"))

    begin
      assert_raises(RawWb::WbClient::RetryableError) do
        RawWb::CommissionTariffSync.new(
          account_scope: RawWb::SellerAccount.where(id: account.id),
          client_factory: ->(_) { failing_client }
        ).run
      end

      assert previous_snapshot.reload.is_current
      failed_snapshot = RawWb::CommissionTariffSnapshot.where(source_account_id: account.id, status: "failed").sole
      assert_equal "RawWb::WbClient::RetryableError", failed_snapshot.error_class
      assert_equal 0, RawWb::CommissionTariff.where(snapshot_id: failed_snapshot.id).count
    ensure
      cleanup_account(account)
    end
  end

  test "falls back to the next account when the preferred account fails" do
    primary = create_account("fallback-primary")
    backup = create_account("fallback-backup")
    failing_client = FakeWbClient.new(error: RawWb::WbClient::ApiError.new("boom"))
    working_client = FakeWbClient.new(response: official_report_payload)

    begin
      result = RawWb::CommissionTariffSync.new(
        account_scope: RawWb::SellerAccount.where(id: [ primary.id, backup.id ]).order(:id),
        client_factory: ->(account) { account.id == primary.id ? failing_client : working_client }
      ).run

      assert_equal backup.id, result[:account_id]
      assert_equal 1, failing_client.calls
      assert_equal 1, working_client.calls
      assert_equal 0, RawWb::CommissionTariffSnapshot.where(source_account_id: primary.id, status: "succeeded").count
    ensure
      cleanup_account(primary)
      cleanup_account(backup)
    end
  end

  test "does not fall back when the preferred response fails validation" do
    primary = create_account("validation-primary")
    backup = create_account("validation-backup")
    invalid_client = FakeWbClient.new(response: { "report" => [ { "subjectName" => "missing id" } ] })
    backup_client = FakeWbClient.new(response: official_report_payload)

    begin
      assert_raises(RawWb::CommissionTariffSync::InvalidResponseError) do
        RawWb::CommissionTariffSync.new(
          account_scope: RawWb::SellerAccount.where(id: [ primary.id, backup.id ]).order(:id),
          client_factory: ->(account) { account.id == primary.id ? invalid_client : backup_client }
        ).run
      end

      assert_equal 1, invalid_client.calls
      assert_equal 0, backup_client.calls
      assert_equal 1, RawWb::CommissionTariffSnapshot.where(source_account_id: primary.id, status: "failed").count
    ensure
      cleanup_account(primary)
      cleanup_account(backup)
    end
  end

  test "rejects non-numeric tariff values before persistence" do
    account = create_account("invalid-rate")
    client = FakeWbClient.new(response: {
      "report" => [ { "subjectID" => 3319, "kgvpMarketplace" => "not-a-number" } ]
    })

    begin
      assert_raises(RawWb::CommissionTariffSync::InvalidResponseError) do
        RawWb::CommissionTariffSync.new(
          account_scope: RawWb::SellerAccount.where(id: account.id),
          client_factory: ->(_) { client }
        ).run
      end

      assert_equal 0, RawWb::CommissionTariff.where(
        snapshot_id: RawWb::CommissionTariffSnapshot.where(source_account_id: account.id).select(:id)
      ).count
    ensure
      cleanup_account(account)
    end
  end

  test "does not query other accounts once the preferred account succeeds" do
    primary = create_account("no-fallback-primary")
    backup = create_account("no-fallback-backup")
    primary_client = FakeWbClient.new(response: official_report_payload)
    backup_client = FakeWbClient.new(response: official_report_payload)

    begin
      RawWb::CommissionTariffSync.new(
        account_scope: RawWb::SellerAccount.where(id: [ primary.id, backup.id ]).order(:id),
        client_factory: ->(account) { account.id == primary.id ? primary_client : backup_client }
      ).run

      assert_equal 1, primary_client.calls
      assert_equal 0, backup_client.calls
    ensure
      cleanup_account(primary)
      cleanup_account(backup)
    end
  end

  test "each successful run leaves exactly one current snapshot even after repeated syncs" do
    account = create_account("repeat")
    client = FakeWbClient.new(response: official_report_payload)

    begin
      3.times do
        RawWb::CommissionTariffSync.new(
          account_scope: RawWb::SellerAccount.where(id: account.id),
          client_factory: ->(_) { client }
        ).run
      end

      assert_equal 1, RawWb::CommissionTariffSnapshot.where(is_current: true).count
      assert_equal 3, RawWb::CommissionTariffSnapshot.where(source_account_id: account.id, status: "succeeded").count
    ensure
      cleanup_account(account)
    end
  end

  test "runs within the platform sync lock" do
    calls = []
    with_singleton_method(SyncRunLock, :with_lock, ->(name, wait:, logger:) {
      calls << [ name, wait, logger ]
      :locked
    }) do
      assert_equal :locked, RawWb::CommissionTariffSync.run
    end

    assert_equal [ [ RawWb::CommissionTariffSync::LOCK_NAME, false, Rails.logger ] ], calls
  end

  test "skips automatically when the lock is busy" do
    called = false
    release_lock = Queue.new
    lock_ready = Queue.new

    holder = Thread.new do
      SyncRunLock.with_lock(RawWb::CommissionTariffSync::LOCK_NAME, wait: true, logger: Rails.logger) do
        lock_ready << true
        release_lock.pop
      end
    end

    lock_ready.pop
    begin
      with_singleton_method(RawWb::CommissionTariffSync, :new, ->(*) {
        called = true
        raise "commission tariff sync should not start while lock is busy"
      }) do
        result = RawWb::CommissionTariffSync.run
        assert_equal({ skipped: true, reason: "lock_busy" }, result)
      end
    ensure
      release_lock << true
      holder.join
    end

    refute called
  end

  private

  def with_singleton_method(klass, method_name, replacement)
    original = klass.method(method_name)
    klass.define_singleton_method(method_name, replacement)
    yield
  ensure
    klass.define_singleton_method(method_name, original)
  end
end
