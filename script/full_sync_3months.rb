#!/usr/bin/env ruby
# 全量拉取近 3 个月数据（WB + Ozon 所有接口）
# 用法：bundle exec rails runner script/full_sync_3months.rb

$stdout.sync = true
Rails.logger = ActiveSupport::Logger.new($stdout)
Rails.logger.level = :info

DAYS = 90

SYNC_START = Time.current

def elapsed
  s = (Time.current - SYNC_START).to_i
  format('%02d:%02d:%02d', s / 3600, s % 3600 / 60, s % 60)
end

def section(title)
  puts "\n#{'=' * 60}"
  puts "  [#{elapsed}] #{title}"
  puts "=" * 60
end

def run_sync(klass, days:)
  t0 = Time.current
  puts "\n[#{elapsed}] 启动 #{klass.name} (days=#{days})"
  results = klass.run(days: days)
  elapsed_sec = (Time.current - t0).to_i
  results.each do |account_id, steps|
    ok  = steps.count { |_, v| v[:ok] }
    err = steps.count { |_, v| v[:error] }
    puts "[#{elapsed}] 账号 ##{account_id}: #{ok} 成功 / #{err} 失败  (#{elapsed_sec}s)"
    steps.select { |_, v| v[:error] }.each do |step, v|
      puts "    ✗ #{step}: #{v[:error]}"
    end
  end
rescue => e
  puts "[#{elapsed}] [ERROR] #{klass.name} 整体失败: #{e.class} — #{e.message}"
end

# ── WB ────────────────────────────────────────────────────────────────────────

section "WB SetupSync（静态数据：账号/类目/仓库）"
run_sync(RawWb::SetupSync, days: DAYS)

section "WB DailySync（交易数据：订单/库存/评价/财务，近 #{DAYS} 天）"
run_sync(RawWb::DailySync, days: DAYS)

section "WB WeeklySync（分析数据：广告/报表/搜索词，近 #{DAYS} 天）"
run_sync(RawWb::WeeklySync, days: DAYS)

# ── Ozon ──────────────────────────────────────────────────────────────────────

section "Ozon SetupSync（静态数据：账号/类目/仓库）"
run_sync(RawOzon::SetupSync, days: DAYS)

section "Ozon WeeklySync（商品/分析/促销/财务对账，近 #{DAYS} 天）"
run_sync(RawOzon::WeeklySync, days: DAYS)

section "Ozon DailySync（发货单/退货/评价/财务流水，近 #{DAYS} 天）"
run_sync(RawOzon::DailySync, days: DAYS)

section "Ozon PerformanceSync（广告效果，近 #{DAYS} 天）"
run_sync(RawOzon::PerformanceSync, days: DAYS)

puts "\n\n✓ 全量同步完成 #{Time.current.strftime('%Y-%m-%d %H:%M:%S')}"
