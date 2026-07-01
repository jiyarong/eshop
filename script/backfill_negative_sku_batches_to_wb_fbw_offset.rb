# frozen_string_literal: true

# 用法:
#   bundle exec rails runner script/backfill_negative_sku_batches_to_wb_fbw_offset.rb
#   DRY_RUN=1 bundle exec rails runner script/backfill_negative_sku_batches_to_wb_fbw_offset.rb

dry_run = ActiveModel::Type::Boolean.new.cast(ENV["DRY_RUN"])

scope = Ec::SkuBatch.where("received_quantity < 0").where.not(batch_type: :wb_fbw_offset)
count = scope.count

puts "Negative sku batches to backfill: #{count}"

if dry_run
  scope.order(:id).limit(20).pluck(:id, :sku_code, :batch_code, :received_quantity, :batch_type).each do |row|
    puts row.join(" | ")
  end
  puts "DRY_RUN=1, no data changed."
else
  updated = scope.update_all(batch_type: Ec::SkuBatch.batch_types[:wb_fbw_offset], updated_at: Time.current)
  puts "Updated sku batches: #{updated}"
end
