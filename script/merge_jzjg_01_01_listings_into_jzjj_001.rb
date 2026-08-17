# frozen_string_literal: true

# Preview (default):
#   bundle exec rails runner script/merge_jzjg_01_01_listings_into_jzjj_001.rb
#
# Apply:
#   APPLY=1 bundle exec rails runner script/merge_jzjg_01_01_listings_into_jzjj_001.rb
#
# Override the merge direction when needed:
#   SOURCE_SKU=JZJJ-001 TARGET_SKU=JZJG-01_01 APPLY=1 \
#     bundle exec rails runner script/merge_jzjg_01_01_listings_into_jzjj_001.rb

source_sku_code = ENV.fetch("SOURCE_SKU", "JZJG-01_01").strip.upcase
target_sku_code = ENV.fetch("TARGET_SKU", "JZJJ-001").strip.upcase
apply = ENV["APPLY"] == "1"

abort "SOURCE_SKU and TARGET_SKU must be different" if source_sku_code == target_sku_code

source_sku = Ec::Sku.find_by(sku_code: source_sku_code)
target_sku = Ec::Sku.find_by(sku_code: target_sku_code)

abort "Source SKU not found: #{source_sku_code}" unless source_sku
abort "Target SKU not found: #{target_sku_code}" unless target_sku

source_listings = Ec::SkuProduct
  .where(sku_code: source_sku.sku_code)
  .includes(:store)
  .order(:store_id, :id)
  .to_a

puts "Listing merge: #{source_sku.sku_code} -> #{target_sku.sku_code}"
puts "Source listings: #{source_listings.size}"

source_listings.each do |listing|
  puts [
    "id=#{listing.id}",
    "platform=#{listing.platform}",
    "store=#{listing.store.store_name}",
    "product_id=#{listing.product_id}",
    "offer_id=#{listing.offer_id.presence || '-'}",
    "platform_sku_id=#{listing.platform_sku_id.presence || '-'}"
  ].join(" | ")
end

if source_listings.empty?
  puts "Nothing to merge."
  exit
end

unless apply
  puts "Preview only; no data changed. Re-run with APPLY=1 to merge these listings."
  exit
end

listing_ids = source_listings.map(&:id)
now = Time.current
updated_listings = 0
updated_actions = 0

Ec::Sku.transaction do
  # Lock both ownership records and re-read the source listing set so concurrent
  # binding changes cannot leave operation history pointing at the wrong SKU.
  Ec::Sku.where(id: [source_sku.id, target_sku.id]).lock.load
  locked_listings = Ec::SkuProduct.where(sku_code: source_sku.sku_code).order(:id).lock.to_a

  if locked_listings.map(&:id) != listing_ids.sort
    raise ActiveRecord::Rollback, "Source listings changed after preview; nothing was updated"
  end

  updated_actions = Ec::OperationAction
    .where(ec_sku_product_id: listing_ids, ec_sku_id: source_sku.id)
    .update_all(ec_sku_id: target_sku.id, updated_at: now)

  updated_listings = Ec::SkuProduct
    .where(id: listing_ids)
    .update_all(sku_code: target_sku.sku_code, updated_at: now)
end

unless updated_listings == listing_ids.size
  abort "Merge aborted because the source listings changed concurrently; no data was updated."
end

puts "Merged listings: #{updated_listings}"
puts "Updated listing operation actions: #{updated_actions}"
puts "Source SKU was retained; inventory, costs, orders, and other SKU data were not changed."
