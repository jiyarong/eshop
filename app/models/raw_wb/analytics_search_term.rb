module RawWb
  class AnalyticsSearchTerm < ApplicationRecord
    self.table_name = 'raw_wb_analytics_search_terms'

    TOP_ORDER_BY_VALUES = %w[openCard addToCart openToCart orders cartToOrder].freeze

    belongs_to :account, class_name: 'RawWb::SellerAccount'

    validates :period_from, :period_to, :keyword, :nm_id, :top_order_by, :synced_at, presence: true
    validates :top_order_by, inclusion: { in: TOP_ORDER_BY_VALUES }
    validate :period_is_natural_week

    scope :for_period, ->(period_from, period_to) { where(period_from: period_from, period_to: period_to) }

    private

    def period_is_natural_week
      return if period_from.blank? || period_to.blank?
      return if period_from.monday? && period_to.sunday? && period_to == period_from + 6.days

      errors.add(:period_to, :invalid)
    end
  end
end
