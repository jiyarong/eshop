module RawWb
  class SearchReportProduct < ApplicationRecord
    self.table_name = "raw_wb_search_report_products"

    belongs_to :account, class_name: "RawWb::SellerAccount"

    validates :period_from, :period_to, :nm_id, :synced_at, presence: true
    validate :period_is_natural_week

    scope :for_period, ->(period_from, period_to) { where(period_from:, period_to:) }

    private

    def period_is_natural_week
      return if period_from.blank? || period_to.blank?
      return if period_from.monday? && period_to.sunday? && period_to == period_from + 6.days

      errors.add(:period_to, :invalid)
    end
  end
end
