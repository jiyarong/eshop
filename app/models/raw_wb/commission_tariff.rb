module RawWb
  class CommissionTariff < ApplicationRecord
    self.table_name = "raw_wb_commission_tariffs"

    belongs_to :snapshot, class_name: "RawWb::CommissionTariffSnapshot"
  end
end
