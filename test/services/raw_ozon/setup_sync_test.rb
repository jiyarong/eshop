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

  private

  def with_singleton_method(klass, method_name, replacement)
    original = klass.method(method_name)
    klass.define_singleton_method(method_name, replacement)
    yield
  ensure
    klass.define_singleton_method(method_name, original)
  end
end
