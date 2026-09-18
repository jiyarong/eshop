require "test_helper"
require "securerandom"

class RawWb::CommissionTariffTest < ActiveSupport::TestCase
  setup do
    @account = RawWb::SellerAccount.create!(
      name: "wb-tariff-#{SecureRandom.hex(6)}",
      api_token: "token-#{SecureRandom.hex(6)}",
      company_type: "small"
    )
    @snapshot = RawWb::CommissionTariffSnapshot.create!(
      status: "succeeded", source_account: @account, locale: "ru",
      fetched_at: Time.current, completed_at: Time.current
    )
  end

  teardown do
    RawWb::CommissionTariff.where(snapshot_id: @snapshot.id).delete_all
    RawWb::CommissionTariffSnapshot.where(id: @snapshot.id).delete_all
    RawWb::SellerAccount.where(id: @account.id).delete_all
  end

  test "wb_subject_id is unique within a snapshot" do
    RawWb::CommissionTariff.create!(
      snapshot: @snapshot, wb_subject_id: 3319, kgvp_marketplace: 21, paid_storage_kgvp: 17.5
    )

    assert_raises(ActiveRecord::RecordNotUnique) do
      RawWb::CommissionTariff.create!(
        snapshot: @snapshot, wb_subject_id: 3319, kgvp_marketplace: 22, paid_storage_kgvp: 18
      )
    end
  end
end
