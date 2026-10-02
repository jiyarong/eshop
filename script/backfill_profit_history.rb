# 周利润归集历史数据回填（一次性脚本）。
#
# 用法（默认只打印计划，不写库；加 EXECUTE=1 才真正拉取并写库）：
#   PLATFORM=ozon ACCOUNT_ID=1 FROM=2025-01-20 TO=2026-03-30 bin/rails runner script/backfill_profit_history.rb
#   PLATFORM=wb   ACCOUNT_ID=3 FROM=2025-01-27 TO=2026-04-30 EXECUTE=1 bin/rails runner script/backfill_profit_history.rb
#
# 环境变量：
#   PLATFORM    ozon | wb（必填）
#   ACCOUNT_ID  raw_ozon_seller_accounts / raw_wb_seller_accounts 的 id（必填）
#   FROM, TO    回填区间（含），YYYY-MM-DD（必填）；TO 通常取库里现有最早数据的前一天
#   WINDOW_DAYS 每个窗口的天数，默认 28
#   SKIP_ADS=1  跳过广告相关步骤
#   EXECUTE=1   真正执行
#
# 所有步骤均幂等：Ozon 财务按天先删后插，WB 财务明细 upsert，广告按周已存在则跳过。
# 中断后用 FROM=<上次打印的最后一个窗口起始日> 重跑即可续跑。
$stdout.sync = true

platform   = ENV.fetch("PLATFORM").to_s
account_id = Integer(ENV.fetch("ACCOUNT_ID"))
from_date  = Date.iso8601(ENV.fetch("FROM"))
to_date    = Date.iso8601(ENV.fetch("TO"))
window     = Integer(ENV.fetch("WINDOW_DAYS", "28"))
execute    = ENV["EXECUTE"] == "1"
skip_ads   = ENV["SKIP_ADS"] == "1"

abort "FROM must not be after TO" if from_date > to_date
abort "TO must not be in the future" if to_date > Date.current
abort "PLATFORM must be ozon or wb" unless %w[ozon wb].include?(platform)

def say(message)
  puts "[#{Time.current.strftime('%F %T')}] #{message}"
end

windows = []
cursor  = from_date
while cursor <= to_date
  window_end = [cursor + window - 1, to_date].min
  windows << [cursor, window_end]
  cursor = window_end + 1
end

# 完整自然周（周一~周日）；周日晚于今天的最后一周按今天截断，与每周同步的存储方式一致。
weeks = []
monday = from_date.beginning_of_week(:monday)
while monday <= to_date
  weeks << [monday, [monday + 6, Date.current].min]
  monday += 7
end

account = platform == "ozon" ? RawOzon::SellerAccount.find(account_id) : RawWb::SellerAccount.find(account_id)
say "#{platform} account##{account_id} #{from_date}..#{to_date}: #{windows.size} windows, #{weeks.size} natural weeks, execute=#{execute}"

if platform == "ozon"
  steps = %i[sync_finance_accrual_by_day sync_postings_fbs sync_postings_fbo]
  say "steps per window: #{steps.join(', ')}; then sync_posting_destinations once"
  unless skip_ads
    say "ads: #{account.performance_client_id.present? ? 'per natural week via PerformanceSync (existing weeks skipped)' : 'no Performance credentials, skipped'}"
  end
  exit unless execute

  windows.each do |ws, we|
    say "window #{ws}..#{we}"
    RawOzon::DailySync.new(account, days: (Date.current - ws).to_i, to: we).run(sync_keys: steps)
  end

  say "posting destinations"
  RawOzon::DailySync.new(account, days: 1).run(sync_keys: %i[sync_posting_destinations])

  if !skip_ads && account.performance_client_id.present?
    RawOzon::PerformanceSync.new(account, days: 14).run(sync_keys: %i[sync_ad_units])
    weeks.each do |wf, wt|
      if RawOzon::PerformanceSkuSpend.where(account_id: account.id, period_from: wf, period_to: wt).exists?
        say "ads week #{wf}..#{wt} already present, skipped"
        next
      end
      say "ads week #{wf}..#{wt}"
      RawOzon::PerformanceSync.new(account, from_date: wf, to_date: wt)
        .run(sync_keys: %i[sync_performance_ppc_sku_spends sync_performance_promotion_sku_spends])
    end
  end
else
  steps = %i[sync_sales_reports sync_sales_report_items sync_finance_details sync_paid_storage]
  say "steps per window: #{steps.join(', ')}; ads: per natural week via sync_ad_settled_fees_for_period (existing weeks skipped)"
  exit unless execute

  windows.each do |ws, we|
    say "window #{ws}..#{we}"
    RawWb::WeeklySync.new(account, days: (Date.current - ws).to_i, to: we).run(sync_keys: steps)
  end

  unless skip_ads
    ad_sync = RawWb::WeeklySync.new(account, days: 1)
    weeks.each do |wf, wt|
      if RawWb::AdSettledFee.where(account_id: account.id, period_from: wf, period_to: wt).exists?
        say "ads week #{wf}..#{wt} already present, skipped"
        next
      end
      say "ads week #{wf}..#{wt}"
      ad_sync.sync_ad_settled_fees_for_period(wf, wt)
      sleep 1
    end
  end
end

say "done"
