require "test_helper"

class RawOzonDailySyncTest < ActiveSupport::TestCase
  test "does not call the retired finance transaction list endpoint" do
    assert_not_includes RawOzon::DailySync::STEPS, :sync_finance_transactions
  end

  test "keeps the accrual-based finance sync" do
    assert_includes RawOzon::DailySync::STEPS, :sync_finance_accrual_by_day
  end
end
