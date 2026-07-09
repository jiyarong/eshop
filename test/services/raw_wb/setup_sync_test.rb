require "test_helper"

class RawWbSetupSyncTest < ActiveSupport::TestCase
  test "run merges active store sync results and order import result" do
    token = SecureRandom.hex(6)
    account = RawWb::SellerAccount.create!(
      name: "wb-setup-#{token}",
      api_token: "token-#{token}",
      company_type: "small"
    )
    store = Ec::Store.create!(
      platform: "wb",
      store_name: "wb-setup-store-#{token}",
      company_type: "small",
      wb_raw_account_id: account.id,
      is_active: true
    )

    with_singleton_method(RawWb::SetupSync, :new, ->(*) {
      Object.new.tap do |runner|
        runner.define_singleton_method(:run) { |sync_keys: nil| { sync_ping: { ok: 1 } } }
      end
    }) do
      with_singleton_method(Ec::OrderImport::Wb, :new, -> {
        Object.new.tap do |importer|
          importer.define_singleton_method(:call) { |synced_since: nil| 3 }
        end
      }) do
        result = RawWb::SetupSync.run(sync_keys: [:sync_ping])

        assert_equal({ sync_ping: { ok: 1 } }, result[store.id])
        assert_equal({ ok: 3 }, result[:order_import])
      end
    end
  ensure
    Ec::Store.where(id: store&.id).delete_all
    RawWb::SellerAccount.where(id: account&.id).delete_all
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
