require "test_helper"

class RawOzonRegisterStoreTest < ActiveSupport::TestCase
  test "creates a store with the account's credentials when none exists" do
    token = SecureRandom.hex(6)
    account = RawOzon::SellerAccount.create!(
      client_id: "ozon-register-#{token}",
      company_name: "ozon-register-company-#{token}",
      api_key: "key-#{token}",
      performance_client_id: "perf-id-#{token}",
      performance_client_secret: "perf-secret-#{token}",
      company_type: "general",
      raw_json: {}
    )

    runner = RawOzon::SetupSync.new(account, days: 1)
    runner.sync_register_store

    store = Ec::Store.find_by!(platform: "ozon", ozon_raw_account_id: account.id)
    assert_equal account.client_id, store.ozon_client_id
    assert_equal account.api_key, store.ozon_api_key
    assert_equal account.performance_client_id, store.ozon_performance_client_id
    assert_equal account.performance_client_secret, store.ozon_performance_client_secret
  ensure
    Ec::Store.where(id: store&.id).delete_all
    RawOzon::SellerAccount.where(id: account&.id).delete_all
  end

  test "refreshes stale credentials on an existing store without touching manually edited fields" do
    token = SecureRandom.hex(6)
    account = RawOzon::SellerAccount.create!(
      client_id: "ozon-register-#{token}",
      api_key: "fresh-key-#{token}",
      performance_client_id: "fresh-perf-id-#{token}",
      performance_client_secret: "fresh-perf-secret-#{token}",
      company_type: "general",
      raw_json: {}
    )
    store = Ec::Store.create!(
      platform: "ozon",
      store_name: "manually renamed store",
      company_type: "small",
      is_active: false,
      ozon_raw_account_id: account.id,
      ozon_client_id: account.client_id,
      ozon_api_key: "stale-key-#{token}",
      ozon_performance_client_id: "stale-perf-id-#{token}",
      ozon_performance_client_secret: "stale-perf-secret-#{token}"
    )

    runner = RawOzon::SetupSync.new(account, days: 1)
    runner.sync_register_store

    store.reload
    assert_equal account.api_key, store.ozon_api_key
    assert_equal account.performance_client_id, store.ozon_performance_client_id
    assert_equal account.performance_client_secret, store.ozon_performance_client_secret
    assert_equal "manually renamed store", store.store_name
    assert_equal "small", store.company_type
    assert_equal false, store.is_active
  ensure
    Ec::Store.where(id: store&.id).delete_all
    RawOzon::SellerAccount.where(id: account&.id).delete_all
  end
end
