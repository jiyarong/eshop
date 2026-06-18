#!/usr/bin/env ruby
# frozen_string_literal: true
#
# 探测 GET /api/marketplace/v3/fbs/orders/archive
# 必填: year, month, next(从0开始), limit(100..1000)
# 用法: rails runner wb_documents/test_archive_orders.rb
#
require 'net/http'
require 'json'

TOKEN = RawWb::SellerAccount.first&.api_token
abort "DB 无 seller account" if TOKEN.blank?

BASE = 'https://marketplace-api.wildberries.ru'

def get_json(path, params)
  uri = URI("#{BASE}#{path}")
  uri.query = URI.encode_www_form(params)
  req = Net::HTTP::Get.new(uri)
  req['Authorization'] = TOKEN
  req['Content-Type'] = 'application/json'
  resp = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 30) { |h| h.request(req) }
  headers = {}
  resp.each_header { |k, v| headers[k] = v if k.match?(/rate|retry|limit/i) }
  [resp.code.to_i, JSON.parse(resp.body.presence || '{}'), headers]
end

# ── 测试1: 当月第一页 ──────────────────────────────────────────────────────
now = Time.current
puts "\n=== 测试1: #{now.year}-#{now.month}, next=0, limit=100 ==="
code, data, hdrs = get_json('/api/marketplace/v3/fbs/orders/archive',
                             year: now.year, month: now.month, next: 0, limit: 100)
puts "HTTP #{code}, rate headers: #{hdrs}"
puts "响应 keys: #{data.keys}"

orders = data['orders'] || []
puts "本月订单数（本页）: #{orders.size}, next_cursor=#{data['next']}"

if (sample = orders.first)
  puts "\n── 单条字段展示 ──"
  sample.each do |k, v|
    puts "  %-18s => %s" % [k, v.inspect.truncate(80)]
  end

  # 价格单位判断
  pi = sample['priceInfo'] || {}
  puts "\n价格字段(priceInfo): #{pi.inspect}"
  puts "注意: 若 price 接近整数售价(如 1000-5000)则单位是卢布; 若很大则是戈比"
end

# ── 测试2: 去年某月(验证历史数据) ─────────────────────────────────────────
puts "\n=== 测试2: #{now.year - 1}-1, next=0, limit=100 ==="
code2, data2, hdrs2 = get_json('/api/marketplace/v3/fbs/orders/archive',
                                year: now.year - 1, month: 1, next: 0, limit: 100)
puts "HTTP #{code2}, rate headers: #{hdrs2}"
puts "订单数: #{(data2['orders'] || []).size}, next=#{data2['next']}"

# ── 测试3: 连发5页(no sleep)测429 ─────────────────────────────────────────
puts "\n=== 测试3: 连发5次请求(no sleep), 观察429和rate limit耗尽 ==="
cursor = 0
5.times do |i|
  t0 = Time.now
  c, d, h = get_json('/api/marketplace/v3/fbs/orders/archive',
                      year: now.year, month: now.month, next: cursor, limit: 100)
  elapsed = Time.now - t0
  nc = d['next'].to_i
  puts "Req #{i + 1}: HTTP #{c}, orders=#{(d['orders'] || []).size}, next=#{nc}, elapsed=#{elapsed.round(2)}s, rl_remaining=#{h['x-ratelimit-remaining']}"
  break if c == 429
  cursor = nc
  break if nc.zero?
end

# ── 测试4: 字段对照(与 raw_wb_orders 表列对照) ───────────────────────────
puts "\n=== 测试4: 关键字段与 raw_wb_orders 表列对照 ==="
if (sample = (data['orders'] || []).first)
  mapping = {
    'id'                        => sample['id'],
    'orderUid'                  => sample['orderUid'],
    'rid(→srid)'                => sample['rid'],
    'deliveryType(缺失?)'       => sample['deliveryType'],
    'product.nmId'              => sample.dig('product', 'nmId'),
    'product.chrtId'            => sample.dig('product', 'chrtId'),
    'product.article'           => sample.dig('product', 'article'),
    'product.skus[0]'           => Array(sample.dig('product', 'skus')).first,
    'status.supplierStatus'     => sample.dig('status', 'supplierStatus'),
    'status.wbStatus'           => sample.dig('status', 'wbStatus'),
    'priceInfo.price'           => sample.dig('priceInfo', 'price'),
    'priceInfo.convertedPrice'  => sample.dig('priceInfo', 'convertedPrice'),
    'priceInfo.currencyCode'    => sample.dig('priceInfo', 'currencyCode'),
    'warehouseId'               => sample['warehouseId'],
    'supplyId'                  => sample['supplyId'],
    'isZeroOrder'               => sample['isZeroOrder'],
    'createdAt'                 => sample['createdAt'],
    'metaDetails'               => sample['metaDetails']&.inspect&.truncate(60),
    'stickerId'                 => sample['stickerId'],
    'cargoType'                 => sample['cargoType'],
  }
  mapping.each { |k, v| puts "  %-32s => %s" % [k, v.inspect] }
end

# ── 测试5: 查 DB 最早订单日期，确定补录范围 ──────────────────────────────
earliest = RawWb::Order.minimum(:created_at)
puts "\n=== DB 当前状况 ==="
puts "raw_wb_orders 总数: #{RawWb::Order.count}"
puts "最早订单 created_at: #{earliest}"
puts "建议补录范围: #{earliest&.strftime('%Y-%m')} 或更早 → #{now.strftime('%Y-%m')}"