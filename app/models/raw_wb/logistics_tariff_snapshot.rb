module RawWb
  class LogisticsTariffSnapshot < ApplicationRecord
    self.table_name = "raw_wb_logistics_tariff_snapshots"

    enum :status, { running: "running", succeeded: "succeeded", failed: "failed" }, validate: true

    belongs_to :source_account, class_name: "RawWb::SellerAccount"
    has_many :logistics_tariffs,
      class_name: "RawWb::LogisticsTariff",
      foreign_key: :snapshot_id,
      dependent: :destroy

    scope :successful, -> { where(status: "succeeded") }

    def self.current
      successful.find_by(is_current: true)
    end

    def self.for_effective_date(date)
      date = date.to_date
      successful
        .where("effective_from IS NULL OR effective_from <= ?", date)
        .where("effective_to IS NULL OR effective_to > ?", date)
        .order(effective_from: :desc, id: :desc)
        .first
    end
  end
end
