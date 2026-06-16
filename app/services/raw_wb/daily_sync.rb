module RawWb
  # Operational sync — run twice daily (e.g. 8:00 and 20:00).
  # Covers all transactional data that changes throughout the day.
  # Default lookback: 2 days to catch any late-arriving WB updates.
  class DailySync < BaseSync
    DEFAULT_DAYS = 2

    STEPS = %i[
      sync_product_cards
      sync_new_orders
      sync_orders
      sync_stats_orders
      sync_stats_sales
      sync_stocks
      sync_wb_warehouse_stocks
      sync_fbs_stocks
      sync_supplies
      sync_supply_items
      sync_reviews
      sync_questions
      sync_unread_feedbacks
      sync_feedback_counts
      sync_question_counts
      sync_product_prices
      sync_balance
      sync_ad_balance
    ].freeze

    def self.run(days: nil, sync_keys: nil)
      SyncRunLock.with_lock(OrderIncrementalSync::LOCK_NAME, wait: true, logger: Rails.logger) do
        super(days: days, sync_keys: sync_keys)
      end
    end
  end
end
