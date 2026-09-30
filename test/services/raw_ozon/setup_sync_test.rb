require "test_helper"

class RawOzonSetupSyncTest < ActiveSupport::TestCase
  test "run merges active store sync results and order import result" do
    token = SecureRandom.hex(6)
    account = RawOzon::SellerAccount.create!(
      client_id: "ozon-setup-#{token}",
      api_key: "token-#{token}",
      company_type: "general",
      raw_json: {}
    )
    store = Ec::Store.create!(
      platform: "ozon",
      store_name: "ozon-setup-store-#{token}",
      company_type: "general",
      ozon_raw_account_id: account.id,
      ozon_client_id: "ozon-store-#{token}",
      is_active: true
    )

    with_singleton_method(RawOzon::SetupSync, :new, ->(*) {
      Object.new.tap do |runner|
        runner.define_singleton_method(:run) { |sync_keys: nil| { sync_seller_info: { ok: 1 } } }
      end
    }) do
      with_singleton_method(Ec::OrderImport::Ozon, :new, -> {
        Object.new.tap do |importer|
          importer.define_singleton_method(:call) { |synced_since: nil| 4 }
        end
      }) do
        result = RawOzon::SetupSync.run(sync_keys: [:sync_seller_info])

        assert_equal({ sync_seller_info: { ok: 1 } }, result[store.id])
        assert_equal({ ok: 4 }, result[:order_import])
      end
    end
  ensure
    Ec::Store.where(id: store&.id).delete_all
    RawOzon::SellerAccount.where(id: account&.id).delete_all
  end

  test "records daily accrual completion and distinguishes failure from valid zero activity" do
    token = SecureRandom.hex(6)
    account = RawOzon::SellerAccount.create!(client_id: "ozon-evidence-#{token}", api_key: token, company_type: "small")
    sync = RawOzon::DailySync.new(account, days: 8)
    sync.define_singleton_method(:sleep) { |_| }
    sync.define_singleton_method(:sync_finance_accrual_by_day) { 0 }
    sync.run(sync_keys: [:sync_finance_accrual_by_day])
    task = RawOzon::SyncTask.where(account_id: account.id).sole
    assert_equal "done", task.status
    assert_equal 0, task.results.dig("sync_finance_accrual_by_day", "ok")
    assert_equal Date.current.iso8601, task.results.dig("period", "to_date")
    assert task.finished_at.present?

    sync = RawOzon::DailySync.new(account, days: 8)
    sync.define_singleton_method(:sync_finance_accrual_by_day) { raise "accrual incomplete" }
    sync.run(sync_keys: [:sync_finance_accrual_by_day])
    failed = RawOzon::SyncTask.where(account_id: account.id).order(:id).last
    assert_equal "partial", failed.status
    assert_equal "accrual incomplete", failed.results.dig("sync_finance_accrual_by_day", "error")
  ensure
    RawOzon::SyncTask.where(account_id: account&.id).delete_all
    account&.delete
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
