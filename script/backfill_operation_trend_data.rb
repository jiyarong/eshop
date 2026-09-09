#!/usr/bin/env ruby
# frozen_string_literal: true

# Repairs locally imported data used by the SKU operation trend chart.
#
# Preview:
#   bin/rails runner script/backfill_operation_trend_data.rb
# Apply:
#   APPLY=1 bin/rails runner script/backfill_operation_trend_data.rb
# Optional SKU scope:
#   SKU_CODES=DJ001,ZJ004,KJ-217-GD APPLY=1 bin/rails runner script/backfill_operation_trend_data.rb

$stdout.sync = true

apply = ENV["APPLY"] == "1"
sku_codes = ENV.fetch("SKU_CODES", "").split(",").map { |value| value.strip.upcase }.compact_blank.uniq
stats = Hash.new(0)

sku_scope = Ec::SkuProduct.includes(:sku, :store)
sku_scope = sku_scope.where(sku_code: sku_codes) if sku_codes.any?
products = sku_scope.order(:store_id, :id).to_a
product_ids = products.map(&:id)
store_ids = products.map(&:store_id).uniq

puts "Operation trend data backfill"
puts "Mode: #{apply ? 'APPLY' : 'PREVIEW'}"
puts "SKU scope: #{sku_codes.any? ? sku_codes.join(', ') : 'ALL'}"
puts "Listings: #{products.size}"

def update_if_apply(record, attributes, apply)
  record.update_columns(attributes.merge(updated_at: Time.current)) if apply
end

def wb_seller_discount_attributes(stats_order, raw_order)
  return {} unless raw_order && stats_order.price_with_disc.present?

  rate = case raw_order.currency_code.to_i
  when 643
    raw_order.price.to_d / raw_order.converted_price.to_d if raw_order.converted_price.to_d.positive?
  when 933
    stats_order.finished_price.to_d / raw_order.price.to_d if raw_order.price.to_d.positive?
  end
  return {} unless rate&.positive?

  {
    seller_discount_unit_price: (stats_order.price_with_disc / rate).round(2),
    seller_discount_currency_code: "BYN",
    seller_discount_synced_at: stats_order.synced_at || stats_order.last_change_date || Time.current
  }
end

# WB buyer-paid price: Statistics API finishedPrice -> normalized order item.
wb_stores = Ec::Store.where(id: store_ids, platform: "wb").where.not(wb_raw_account_id: nil).index_by(&:wb_raw_account_id)
wb_nm_ids = products.select { |product| product.platform == "wb" }
  .group_by { |product| product.store.wb_raw_account_id }
  .transform_values { |rows| rows.map { |product| product.product_id.to_i }.uniq }
RawWb::StatsOrder.where(account_id: wb_stores.keys).where.not(finished_price: nil, srid: [nil, ""]).find_each do |raw|
  store = wb_stores[raw.account_id]
  next unless store && raw.nm_id.to_i.in?(wb_nm_ids.fetch(raw.account_id, []))

  matches = Ec::OrderItem.joins(:order).where(
    store_id: store.id,
    platform: "wb",
    platform_sku_id: raw.nm_id.to_s,
    ec_orders: { external_order_id: raw.srid }
  ).limit(2).to_a
  if matches.one?
    item = matches.first
    attributes = {}
    if item.buyer_paid_unit_price.nil?
      attributes.merge!(
        buyer_paid_unit_price: raw.finished_price,
        buyer_currency_code: "RUB",
        buyer_paid_synced_at: raw.synced_at || raw.last_change_date || Time.current
      )
      stats[:wb_buyer_paid] += 1
    end
    if item.seller_discount_unit_price.nil?
      raw_order = RawWb::Order.find_by(account_id: raw.account_id, srid: raw.srid)
      seller_attributes = wb_seller_discount_attributes(raw, raw_order)
      attributes.merge!(seller_attributes)
      stats[:wb_seller_discount] += 1 if seller_attributes.any?
    end
    update_if_apply(item, attributes, apply) if attributes.any?
  elsif matches.many?
    stats[:wb_buyer_conflicts] += 1
  else
    stats[:wb_buyer_unmatched] += 1
  end
end

# Ozon buyer-paid price: link imported report rows, then repair linked-but-empty normalized fields.
ozon_stores = Ec::Store.where(id: store_ids, platform: "ozon").where.not(ozon_raw_account_id: nil).index_by(&:ozon_raw_account_id)
ozon_skus = products.select { |product| product.platform == "ozon" }
  .group_by { |product| product.store.ozon_raw_account_id }
  .transform_values { |rows| rows.filter_map { |product| product.platform_sku_id&.to_i }.uniq }
ozon_items = RawOzon::PostingReportItem
  .where(account_id: ozon_skus.keys, ozon_sku: ozon_skus.values.flatten.uniq)
  .where.not(buyer_paid_unit_price: nil)
ozon_items.includes(:ec_order_item).find_each do |raw|
  item = raw.ec_order_item
  unless item
    store = ozon_stores[raw.account_id]
    matches = store && Ec::OrderItem.where(
      platform: "ozon", store_id: store.id,
      external_item_id: "#{raw.posting_number}:#{raw.ozon_sku}"
    ).limit(2).to_a
    if matches&.one?
      item = matches.first
      if RawOzon::PostingReportItem.where(ec_order_item_id: item.id).where.not(id: raw.id).exists?
        stats[:ozon_link_conflicts] += 1
        next
      end
      raw.update_columns(ec_order_item_id: item.id, updated_at: Time.current) if apply
      stats[:ozon_linked] += 1
    elsif matches&.many?
      stats[:ozon_link_conflicts] += 1
      next
    else
      stats[:ozon_link_pending] += 1
      next
    end
  end
  next unless item.buyer_paid_unit_price.nil?
  if RawOzon::PostingReportItem.where(ec_order_item_id: item.id).where.not(id: raw.id).exists?
    stats[:ozon_link_conflicts] += 1
    next
  end

  update_if_apply(item, {
    buyer_paid_unit_price: raw.buyer_paid_unit_price,
    buyer_currency_code: raw.buyer_currency_code,
    buyer_paid_synced_at: raw.synced_at
  }, apply)
  stats[:ozon_buyer_paid] += 1
end

# Repair the confirmed WB historical unit discontinuity. A listing is repaired only when
# one of its Action changes jumps by approximately 100x; only earlier price values change.
price_fields = %w[price final_price]
products.select { |product| product.platform == "wb" }.each do |product|
  actions = product.operation_actions.where(operation_type: "listing_pricing").order(:operated_at, :id).to_a
  boundary = actions.find do |action|
    price_fields.any? do |field|
      change = action.diff_result.to_h.dig("fields", field).to_h
      from = BigDecimal(change["from"].to_s, exception: false)
      to = BigDecimal(change["to"].to_s, exception: false)
      from&.positive? && to&.positive? && (to / from).between?(99, 101)
    end
  end
  next unless boundary

  actions.take(actions.index(boundary) + 1).each do |action|
    diff = action.diff_result.deep_dup
    changed = false
    price_fields.each do |field|
      diff.dig("fields", field).to_h.each do |side, value|
        number = BigDecimal(value.to_s, exception: false)
        next unless number
        next if action == boundary && side == "to"

        diff["fields"][field][side] = (number * 100).to_s("F")
        changed = true
      end
    end
    next unless changed

    update_if_apply(action, { diff_result: diff }, apply)
    stats[:wb_price_actions_repaired] += 1
  end
end

operator = User.where(active: true).joins(:roles).where(roles: { code: "super_admin" }).order(:id).first
products.each do |product|
  unless product.sku
    stats[:price_baselines_missing_sku] += 1
    next
  end

  price_attributes = if product.platform == "wb"
    raw_product = RawWb::Product.find_by(account_id: product.store.wb_raw_account_id, nm_id: product.product_id)
    raw_price = raw_product && RawWb::ProductPrice.find_by(product_id: raw_product.id, account_id: product.store.wb_raw_account_id)
    raw_price && {
      value: raw_price.final_price,
      operated_at: raw_price.updated_at,
      fields: raw_price.attributes.slice("price", "discount", "club_discount", "final_price", "currency_code", "is_in_quarantine")
    }
  elsif product.platform == "ozon"
    raw_price = RawOzon::ProductPrice.find_by(account_id: product.store.ozon_raw_account_id, ozon_product_id: product.product_id)
    raw_price && {
      value: raw_price.price,
      operated_at: raw_price.synced_at,
      fields: raw_price.attributes.slice("price", "customer_price", "old_price", "marketing_price", "min_price", "currency_code")
    }
  end
  next unless price_attributes&.dig(:value).to_d.positive?

  key = product.platform == "wb" ? "final_price" : "price"
  has_price_history = product.operation_actions.where(operation_type: "listing_pricing").any? do |action|
    action.diff_result.to_h.dig("fields", key).present?
  end
  next if has_price_history

  assigned_operator = product.operator_role_assignments.order(:id).first&.user
  action_operator = assigned_operator || operator
  unless action_operator
    stats[:price_baselines_missing_operator] += 1
    next
  end

  fields = price_attributes.fetch(:fields).each_with_object({}) do |(field, value), result|
    result[field] = { "from" => nil, "to" => value } unless value.nil?
  end
  if apply
    action = Ec::OperationAction.new(
      operation_type: "listing_pricing",
      operated_by_user: action_operator,
      operated_at: price_attributes[:operated_at] || Time.current,
      sku_product: product,
      sku: product.sku,
      store: product.store,
      diff_result: { "platform" => product.platform, "backfill_baseline" => true, "fields" => fields },
      record_by_system: true
    )
    unless action.save
      stats[:price_baselines_failed] += 1
      warn "BASELINE ERROR listing=#{product.id} sku=#{product.sku_code} store=#{product.store_id}: #{action.errors.full_messages.join(', ')}"
      next
    end
  end
  stats["#{product.platform}_price_baselines".to_sym] += 1
end

puts "SUMMARY"
stats.sort.each { |key, count| puts "  #{key}: #{count}" }
puts(apply ? "Applied." : "Preview only. Re-run with APPLY=1 to write changes.")
