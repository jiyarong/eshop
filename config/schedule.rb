# Deploy:  bundle exec whenever --update-crontab
# Remove:  bundle exec whenever --clear-crontab
# Preview: bundle exec whenever --dry-run

set :environment, ENV.fetch('RAILS_ENV', 'production')
set :output, { error: 'log/cron_error.log', standard: 'log/cron.log' }

# 每条 cron 命令先 source shared/.env，确保 API keys 等环境变量可用
env_path = '/home/deployer/apps/ecommerce_manage/shared/.env'
set :job_template, "bash -l -c 'set -a; source #{env_path}; set +a; :job'"

# ══════════════════════════════════════════════════════════════════════════════
# PostgreSQL 备份（每日 2:00，保留 5 天）
# ══════════════════════════════════════════════════════════════════════════════

every 1.day, at: '2:00 am' do
  command <<~BASH
    mkdir -p /home/deployer/backups && \
    PGPASSWORD=$ECOMMERCE_MANAGE_DATABASE_PASSWORD pg_dump \
      -h localhost -U ecommerce_manage -Fc \
      ecommerce_manage_production \
      -f /home/deployer/backups/ecommerce_$(date +%Y%m%d).dump && \
    find /home/deployer/backups -name 'ecommerce_*.dump' -mtime +5 -delete
  BASH
end

# ══════════════════════════════════════════════════════════════════════════════
# Wildberries
# ══════════════════════════════════════════════════════════════════════════════

# Daily ×2 — orders, stocks, prices, balance, reviews, chats, return claims
every 1.day, at: '8:00 am' do
  runner 'RawWb::DailySync.run'
end

every 1.day, at: '8:00 pm' do
  runner 'RawWb::DailySync.run'
end

# Weekly — product cards, ads, analytics funnel, search terms, region sale,
#          penalties, deductions, goods return, sales reports.
# days:8 gives 1-day overlap to catch WB's late-arriving settlement data.
# Run Monday 5:30 — 2.5 hr buffer before DailySync at 8:00 to avoid concurrent WB table writes.
every :monday, at: '5:30 am' do
  runner 'RawWb::WeeklySync.run(days: 8)'
end

# Second ad-stats pass mid-week — WB ad data settles T+1, so a Thursday pull
# refreshes numbers for Mon–Wed before the next weekly run.
every :thursday, at: '3:30 am' do
  runner "RawWb::WeeklySync.run(sync_keys: [:sync_ad_campaigns, :sync_ad_stats], days: 4)"
end

# WB paid_storage re-sync + W-1 report refresh — WB storage API has a T+2~3 day lag,
# so Monday's sync misses the last 2 days of the previous week.
# By Thursday all 7 days are finalized; re-sync with days:14 and re-run W-1 only.
# clear_all: false preserves the W-2 tab written on Monday.
every :thursday, at: '5:00 am' do
  runner "RawWb::WeeklySync.run(days: 14, sync_keys: [:sync_paid_storage])"
end

every :thursday, at: '5:30 am' do
  runner "GoogleSheets::WeeklyProfitReportRunner.run(weeks_ago: [1], clear_all: false)"
end

# Monthly — seller info, parent categories, subjects, warehouses
every :month, on: 1, at: '4:00 am' do
  runner 'RawWb::SetupSync.run'
end

# Monthly full stocks resync — WB stocks API only returns recently-changed rows,
# so DailySync(days:2) misses products with no recent movement.
# days:500 guarantees every active product's stock is refreshed at least once a month.
# Use raw cron syntax (2nd of month) to avoid whenever's on: off-by-one bug.
every '0 3 2 * *' do
  runner "RawWb::DailySync.run(days: 500, sync_keys: [:sync_stocks])"
end

# Weekly catchup — these steps are absent from WeeklySync STEPS; a DailySync failure
# leaves a >7-day gap with no safety net. Sunday 2:00 covers the full prior week.
# Includes: orders (FBS source), supplies + supply_items (FBW 送仓),
#           stats_orders / stats_sales (WB stats API settles T+1~3, days:2 can miss late data).
every :sunday, at: '2:00 am' do
  runner "RawWb::DailySync.run(days: 8, sync_keys: [:sync_orders, :sync_supplies, :sync_supply_items, :sync_stats_orders, :sync_stats_sales])"
end

# ══════════════════════════════════════════════════════════════════════════════
# Ozon
# ══════════════════════════════════════════════════════════════════════════════

# Daily ×2 — FBS/FBO postings, returns, stocks, prices, finance transactions,
#            supply orders, chats.
# Offset 30 min from WB to avoid overlapping DB writes.
every 1.day, at: '8:30 am' do
  runner 'RawOzon::DailySync.run'
end

every 1.day, at: '8:30 pm' do
  runner 'RawOzon::DailySync.run'
end

# Weekly — product catalog, analytics, analytics_stocks, promotions,
#          finance_realization.
# Tuesday avoids same-night collision with WB WeeklySync.
every :tuesday, at: '3:00 am' do
  runner 'RawOzon::WeeklySync.run(days: 8)'
end

# Monthly — seller info, categories (9500+ records), warehouses
every :month, on: 1, at: '5:00 am' do
  runner 'RawOzon::SetupSync.run'
end

# ══════════════════════════════════════════════════════════════════════════════
# 库存快照（每日 9:00，WB 8:00 + Ozon 8:30 跑完后聚合写 Sheet）
# ══════════════════════════════════════════════════════════════════════════════

every 1.day, at: '9:00 am' do
  runner 'Ec::InventorySnapshotSync.run_and_push_to_sheets'
end

# ══════════════════════════════════════════════════════════════════════════════
# 周报（WB + Ozon，写 Google Sheets）
# ══════════════════════════════════════════════════════════════════════════════

# 每周一 5:30，从 CBR XML 拉取本周汇率存入 ec_weekly_rates（W-1、W-2 共用本周汇率作兜底）。
every :monday, at: "8:30 am" do
  runner "Ec::CbrRateFetcher.fetch_and_store"
end

# 每周一 15:00，写上上周（W-2）和上周（W-1）的利润周报。
# 汇率优先取 ec_weekly_rates 精确匹配，不中则用最近一条。
# Performance(13:00) + accrual_by_day(13:10) 在前，确保广告费和财务数据就绪。
every :monday, at: "3:00 pm" do
  runner "GoogleSheets::WeeklyProfitReportRunner.run"
end

# ══════════════════════════════════════════════════════════════════════════════
# Ozon Performance (广告效果，独立认证)
# ══════════════════════════════════════════════════════════════════════════════

# 周一 13:00 — 同步 W-2 和 W-1 两个自然周广告数据，period_from/to 精确对齐自然周边界，
# 供周报策略1直接命中，避免周报时实时调 API。拉两周防止结算窗口偏移导致漏数据。
every :monday, at: '1:00 pm' do
  runner <<~RUBY
    w1_from = Date.current.beginning_of_week - 1.week
    w2_from = w1_from - 1.week
    RawOzon::PerformanceSync.run(from_date: w2_from, to_date: w2_from + 6)
    RawOzon::PerformanceSync.run(from_date: w1_from, to_date: w1_from + 6)
  RUBY
end

# 周四 3:00 — 同步本周截至周三的广告数据（T+1 结算延迟补录，非周报用途）。
every :thursday, at: '3:00 am' do
  runner 'RawOzon::PerformanceSync.run'
end

# 周报前置同步：finance_details / paid_storage / ad_campaigns / ad_settled_fees
# 这四个是利润归集的核心数据源，单独提前跑确保周报时已就绪。
# 错开 OzonPerformanceSync（13:00）10 分钟，避免并发 DB 写。
every :monday, at: '1:10 pm' do
  runner "RawWb::WeeklySync.run(days: 8, sync_keys: [:sync_ad_campaigns, :sync_finance_details, :sync_paid_storage, :sync_ad_settled_fees])"
end

# 周一 13:30 — 重新拉取 W-2、W-1 的 accrual_by_day，确保周报用最新财务结算数据。
# days:15 从两周前周一起算，覆盖 W-2 + W-1 全部结算行。
# Ozon 结算数据在自然周结束后数天内仍可能变动，提前刷新避免漏单或多计。
# 错开 WbWeeklySync（13:10）20 分钟，避免并发 DB 写。
every :monday, at: '1:30 pm' do
  runner "RawOzon::DailySync.run(days: 15, sync_keys: [:sync_finance_accrual_by_day])"
end
