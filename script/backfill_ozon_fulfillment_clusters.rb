# frozen_string_literal: true

# 用法:
#   bundle exec rails runner script/backfill_ozon_fulfillment_clusters.rb
#   DRY_RUN=1 bundle exec rails runner script/backfill_ozon_fulfillment_clusters.rb

dry_run = ActiveModel::Type::Boolean.new.cast(ENV["DRY_RUN"])
limit = ENV["LIMIT"].presence&.to_i

source_models = {
  "RawOzon::PostingFbo" => RawOzon::PostingFbo,
  "RawOzon::PostingFbs" => RawOzon::PostingFbs
}.freeze

scope = Ec::OrderFulfillment
  .where(platform: "ozon", raw_source_type: source_models.keys)
  .order(:id)
scope = scope.limit(limit) if limit&.positive?

seen = 0
updated = 0
unchanged = 0
missing_source = 0

scope.find_in_batches(batch_size: 500) do |fulfillments|
  raw_by_type = source_models.transform_values do |model|
    ids = fulfillments
      .select { |fulfillment| fulfillment.raw_source_type == model.name }
      .filter_map(&:raw_source_id)

    ids.empty? ? {} : model.where(id: ids).index_by(&:id)
  end

  fulfillments.each do |fulfillment|
    seen += 1
    raw = raw_by_type.fetch(fulfillment.raw_source_type).fetch(fulfillment.raw_source_id, nil)
    unless raw
      missing_source += 1
      next
    end

    cluster_from = raw.financial_data&.dig("cluster_from").presence
    cluster_to = raw.financial_data&.dig("cluster_to").presence

    if fulfillment.cluster_from == cluster_from && fulfillment.cluster_to == cluster_to
      unchanged += 1
      next
    end

    updated += 1
    if dry_run
      puts [
        fulfillment.id,
        fulfillment.external_fulfillment_id,
        fulfillment.cluster_from,
        cluster_from,
        fulfillment.cluster_to,
        cluster_to
      ].join(" | ")
    else
      fulfillment.update_columns(
        cluster_from: cluster_from,
        cluster_to: cluster_to,
        updated_at: Time.current
      )
    end
  end
end

puts "Ozon fulfillments scanned: #{seen}"
puts "Ozon fulfillments updated: #{dry_run ? 0 : updated}"
puts "Ozon fulfillments needing update: #{updated}" if dry_run
puts "Ozon fulfillments unchanged: #{unchanged}"
puts "Ozon fulfillments missing raw source: #{missing_source}"
puts "DRY_RUN=1, no data changed." if dry_run
