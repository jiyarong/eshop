module RawWb
  class AdvExpense < ApplicationRecord
    self.table_name = "raw_wb_adv_expenses"

    belongs_to :store, class_name: "Ec::Store"
    belongs_to :campaign, class_name: "RawWb::AdvCampaign", optional: true
  end
end
