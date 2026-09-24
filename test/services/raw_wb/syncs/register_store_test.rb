require "test_helper"

class RawWbRegisterStoreTest < ActiveSupport::TestCase
  test "creates a store with the account's token when none exists" do
    token = SecureRandom.hex(6)
    account = RawWb::SellerAccount.create!(
      name: "wb-register-#{token}",
      api_token: "token-#{token}",
      company_type: "small"
    )

    runner = RawWb::SetupSync.new(account, days: 1)
    runner.sync_register_store

    store = Ec::Store.find_by!(platform: "wb", wb_raw_account_id: account.id)
    assert_equal account.api_token, store.wb_api_token
  ensure
    Ec::Store.where(id: store&.id).delete_all
    RawWb::SellerAccount.where(id: account&.id).delete_all
  end

  test "refreshes a stale token on an existing store without touching manually edited fields" do
    token = SecureRandom.hex(6)
    account = RawWb::SellerAccount.create!(
      name: "wb-register-#{token}",
      api_token: "fresh-token-#{token}",
      company_type: "small"
    )
    store = Ec::Store.create!(
      platform: "wb",
      store_name: "manually renamed store",
      company_type: "general",
      is_active: false,
      wb_raw_account_id: account.id,
      wb_api_token: "stale-token-#{token}"
    )

    runner = RawWb::SetupSync.new(account, days: 1)
    runner.sync_register_store

    store.reload
    assert_equal account.api_token, store.wb_api_token
    assert_equal "manually renamed store", store.store_name
    assert_equal "general", store.company_type
    assert_equal false, store.is_active
  ensure
    Ec::Store.where(id: store&.id).delete_all
    RawWb::SellerAccount.where(id: account&.id).delete_all
  end
end
