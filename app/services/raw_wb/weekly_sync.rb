module RawWb
  # Analytics sync — run once per week (e.g. Monday 3:00 am).
  # Covers reports and analytical data that aggregates over multi-day windows.
  # Default lookback: 7 days.
  class WeeklySync < BaseSync
    DEFAULT_DAYS = 7

    STEPS = %i[
      sync_product_cards
      sync_ad_campaign_count
      sync_ad_campaigns
      sync_ad_stats
      sync_region_sale
      sync_goods_return
      sync_sales_reports
      sync_sales_report_items
      sync_finance_details
      sync_paid_storage
      sync_ad_settled_fees
      sync_search_terms
    ].freeze

    # 按需同步指定账号、指定时段的广告费（当报告日期不是自然周边界时调用）
    def self.sync_ad_fees_for_period(account_id:, from_date:, to_date:)
      account = RawWb::SellerAccount.find(account_id)
      new(account, days: 1).sync_ad_settled_fees_for_period(from_date.to_date, to_date.to_date)
    end
  end
end
