require "test_helper"
require "securerandom"

class RawWb::CommissionTariffSnapshotTest < ActiveSupport::TestCase
  setup do
    @account = RawWb::SellerAccount.create!(
      name: "wb-tariff-snapshot-#{SecureRandom.hex(6)}",
      api_token: "token-#{SecureRandom.hex(6)}",
      company_type: "small"
    )
  end

  teardown do
    RawWb::CommissionTariffSnapshot.where(source_account_id: @account.id).delete_all
    RawWb::SellerAccount.where(id: @account.id).delete_all
  end

  test "only one snapshot can be current at a time" do
    RawWb::CommissionTariffSnapshot.create!(
      status: "succeeded", source_account: @account, locale: "ru",
      fetched_at: Time.current, completed_at: Time.current, is_current: true
    )

    assert_raises(ActiveRecord::RecordNotUnique) do
      RawWb::CommissionTariffSnapshot.create!(
        status: "succeeded", source_account: @account, locale: "ru",
        fetched_at: Time.current, completed_at: Time.current, is_current: true
      )
    end
  end

  test ".current returns only a succeeded, is_current snapshot" do
    RawWb::CommissionTariffSnapshot.create!(
      status: "running", source_account: @account, locale: "ru", fetched_at: Time.current
    )
    assert_nil RawWb::CommissionTariffSnapshot.current

    succeeded = RawWb::CommissionTariffSnapshot.create!(
      status: "succeeded", source_account: @account, locale: "ru",
      fetched_at: Time.current, completed_at: Time.current, is_current: true
    )
    assert_equal succeeded, RawWb::CommissionTariffSnapshot.current
  end
end
