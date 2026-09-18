require "test_helper"

class WbCommissionTariffScheduleTest < ActiveSupport::TestCase
  test "syncs the WB commission tariff table monthly" do
    recurring = YAML.safe_load_file(Rails.root.join("config/recurring.yml")).fetch("production")

    assert_equal "every month on the 1st at 4:30 in Asia/Shanghai",
      recurring.dig("wb_commission_tariff_sync", "schedule")
    assert_equal "RawWb::CommissionTariffSync.run",
      recurring.dig("wb_commission_tariff_sync", "command")
  end
end
