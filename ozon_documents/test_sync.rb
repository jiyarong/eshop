# Ozon Sync 逐步测试脚本
# 用法: rails runner ozon_documents/test_sync.rb

require 'pp'
require 'timeout'

# 从数据库读取账号
account = RawOzon::SellerAccount.find_by!(is_active: true)
puts "账号 ID: #{account.id} (client_id: #{account.client_id[0..5]}***)\n\n"

ALL_STEPS = {
  setup: %i[sync_seller_info sync_categories sync_warehouses],
  daily: %i[
    sync_postings_fbs sync_postings_fbo sync_returns
    sync_product_prices sync_product_stocks
    sync_reviews sync_questions sync_chats
    sync_finance_transactions sync_supply_orders
  ],
  weekly: %i[
    sync_products sync_analytics sync_analytics_stocks
    sync_promotions sync_finance_realization
  ],
}

TABLE_MAP = {
  sync_seller_info:          nil,
  sync_categories:           RawOzon::Category,
  sync_warehouses:           RawOzon::Warehouse,
  sync_postings_fbs:         RawOzon::PostingFbs,
  sync_postings_fbo:         RawOzon::PostingFbo,
  sync_returns:              RawOzon::Return,
  sync_product_prices:       RawOzon::ProductPrice,
  sync_product_stocks:       RawOzon::ProductStock,
  sync_reviews:              RawOzon::Review,
  sync_questions:            RawOzon::Question,
  sync_chats:                RawOzon::Chat,
  sync_finance_transactions: RawOzon::FinanceTransaction,
  sync_supply_orders:        RawOzon::SupplyOrder,
  sync_products:             RawOzon::Product,
  sync_analytics:            RawOzon::Analytics,
  sync_analytics_stocks:     RawOzon::AnalyticsStock,
  sync_promotions:           RawOzon::Promotion,
  sync_finance_realization:  RawOzon::FinanceRealization,
}

results  = {}
errors   = {}

syncer = RawOzon::BaseSync.new(account, days: 7)

ALL_STEPS.each do |group, steps|
  puts "=" * 60
  puts "  #{group.to_s.upcase}"
  puts "=" * 60

  steps.each do |step|
    print "  #{step} ... "
    begin
      count = Timeout.timeout(30) { syncer.public_send(step) }
      model = TABLE_MAP[step]
      db_count = model ? model.where(account_id: account.id).count : '-'
      puts "OK (返回 #{count}, DB: #{db_count})"
      results[step] = { ok: count, db: db_count }
    rescue Timeout::Error
      puts "TIMEOUT (>30s，跳过)"
      results[step] = { error: 'Timeout::Error: 超时跳过' }
    rescue => e
      puts "FAIL"
      puts "    #{e.class}: #{e.message.truncate(200)}"
      results[step] = { error: "#{e.class}: #{e.message.truncate(300)}" }
    end
    sleep 1
  end
  puts
end

puts "=" * 60
puts "  汇总"
puts "=" * 60
ok_steps  = results.select { |_, v| v[:ok] }
err_steps = results.select { |_, v| v[:error] }

puts "\n✅ 成功 (#{ok_steps.size}):"
ok_steps.each { |step, v| puts "   #{step}: 拉取 #{v[:ok]} 条, DB #{v[:db]} 条" }

if err_steps.any?
  puts "\n❌ 失败 (#{err_steps.size}):"
  known_skip = {
    sync_reviews:    '需要 Ozon 订阅计划升级（PermissionDenied）',
    sync_questions:  '需要 Premium Plus 订阅（PermissionDenied）',
    sync_chats:      '本地代理干扰 SSL（环境问题，生产环境应正常）',
  }
  err_steps.each do |step, v|
    note = known_skip[step] ? " [已知: #{known_skip[step]}]" : ''
    puts "   #{step}:#{note}\n     #{v[:error]}"
  end
end
puts
