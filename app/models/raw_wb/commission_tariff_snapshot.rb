module RawWb
  class CommissionTariffSnapshot < ApplicationRecord
    self.table_name = "raw_wb_commission_tariff_snapshots"

    enum :status, { running: "running", succeeded: "succeeded", failed: "failed" }, validate: true

    belongs_to :source_account, class_name: "RawWb::SellerAccount"
    has_many :commission_tariffs, class_name: "RawWb::CommissionTariff", foreign_key: :snapshot_id, dependent: :destroy

    def self.current
      find_by(is_current: true, status: "succeeded")
    end
  end
end
