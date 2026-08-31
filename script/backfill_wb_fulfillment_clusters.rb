# frozen_string_literal: true

# Usage:
#   bundle exec rails runner script/backfill_wb_fulfillment_clusters.rb
#   DRY_RUN=1 LIMIT=100 bundle exec rails runner script/backfill_wb_fulfillment_clusters.rb

dry_run = ActiveModel::Type::Boolean.new.cast(ENV["DRY_RUN"])
limit = ENV["LIMIT"].presence&.to_i

scope = Ec::OrderSourceLink
  .where(platform: "wb", source_type: "RawWb::StatsOrder")
  .where.not(fulfillment_id: nil)
  .order(:id)
scope = scope.limit(limit) if limit&.positive?

seen = 0
updated = 0
unchanged = 0
missing_source = 0

scope.find_in_batches(batch_size: 500) do |links|
  stats_orders = RawWb::StatsOrder.where(id: links.map(&:source_id)).index_by(&:id)
  fulfillments = Ec::OrderFulfillment.where(id: links.map(&:fulfillment_id)).index_by(&:id)

  links.each do |link|
    seen += 1
    stats_order = stats_orders[link.source_id]
    fulfillment = fulfillments[link.fulfillment_id]
    unless stats_order && fulfillment
      missing_source += 1
      next
    end

    clusters = RawWb::OrderClusterResolver.resolve(stats_order)
    if fulfillment.cluster_from == clusters[:cluster_from] && fulfillment.cluster_to == clusters[:cluster_to]
      unchanged += 1
      next
    end

    updated += 1
    if dry_run
      puts [fulfillment.id, fulfillment.external_fulfillment_id, clusters[:cluster_from], clusters[:cluster_to]].join(" | ")
    else
      fulfillment.update_columns(**clusters, updated_at: Time.current)
    end
  end
end

puts "WB fulfillments scanned: #{seen}"
puts "WB fulfillments updated: #{dry_run ? 0 : updated}"
puts "WB fulfillments needing update: #{updated}" if dry_run
puts "WB fulfillments unchanged: #{unchanged}"
puts "WB fulfillments missing source: #{missing_source}"
puts "DRY_RUN=1, no data changed." if dry_run
