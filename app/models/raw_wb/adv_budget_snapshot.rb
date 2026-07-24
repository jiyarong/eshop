module RawWb
  class AdvBudgetSnapshot < ApplicationRecord
    self.table_name = "raw_wb_adv_budget_snapshots"

    belongs_to :campaign, class_name: "RawWb::AdvCampaign"
  end
end
