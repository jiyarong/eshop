namespace :wb do
  desc <<~DESC
    Sync past N days of WB data (GET endpoints only).

    Usage:
      rake wb:sync                        # default 7 days, all steps
      rake wb:sync[14]                    # last 14 days, all steps
      rake wb:sync[7,"sync_orders"]       # last 7 days, only sync_orders
      rake wb:sync[7,"sync_orders;sync_reviews;sync_balance"]  # multiple steps (use semicolon)

    Available steps:
      sync_ping, sync_seller_info, sync_categories, sync_warehouses,
      sync_product_prices, sync_new_orders, sync_stats_orders, sync_stats_sales,
      sync_stocks, sync_orders, sync_reviews, sync_questions,
      sync_unread_feedbacks, sync_sales_funnel, sync_balance, sync_ad_campaign_count

    Requires: WB_API_KEY env var (will find or create SellerAccount with this token)
  DESC
  task :sync, [:days, :sync_keys] => :environment do |_, args|
    days      = args[:days].presence&.to_i || 7
    # Remove quotes and split by semicolon
    sync_keys = args[:sync_keys].presence&.gsub(/['"]/,'')&.split(';')&.map(&:strip)

    raise ArgumentError, 'WB_API_KEY environment variable is required' if ENV['WB_API_KEY'].blank?

    start_time = Time.current
    if sync_keys
      puts "[WbSync] Starting — days=#{days}, steps=#{sync_keys.join(',')}"
    else
      puts "[WbSync] Starting — days=#{days}, all steps"
    end

    results = RawWb::WeeklySync.run(days: days, sync_keys: sync_keys)

    elapsed = (Time.current - start_time).round(1)
    puts "[WbSync] Finished in #{elapsed}s"

    if results.is_a?(Hash)
      results.each do |step, outcome|
        status = outcome[:error] ? "✗ #{outcome[:error]}" : "✓ #{outcome[:ok]} records"
        puts "  #{step}: #{status}"
      end
    end
  end
end
