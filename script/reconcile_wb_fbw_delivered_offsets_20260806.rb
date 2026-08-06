# frozen_string_literal: true

# Reconciles WB FBW offsets against the official delivered quantities for
# 2025-01-01 through 2026-08-06 (Europe/Moscow).
#
# Preview:
#   bundle exec rails runner script/reconcile_wb_fbw_delivered_offsets_20260806.rb
# Apply:
#   APPLY=1 bundle exec rails runner script/reconcile_wb_fbw_delivered_offsets_20260806.rb

class WbFbwDeliveredOffsetReconciler20260806
  BATCH_PREFIX = "WB-FBW-DELIVERED-20260806"
  SOURCE_NOTE = "WB official delivered reconciliation, 2025-01-01..2026-08-06 MSK"

  # sku => [official delivered, FBS delivered, FBW delivered]
  SOURCE_ROWS = {
    "CYQ95-BK" => [0, 0, 0],
    "CYQ97-BK" => [426, 383, 23],
    "CYQ97-WT" => [578, 511, 38],
    "CZY001" => [49, 45, 4],
    "JD-ZQTB-206" => [369, 96, 97],
    "JD-ZQTB310" => [126, 36, 25],
    "JDCCJ-01" => [173, 156, 0],
    "JXZ-GREY-01" => [306, 96, 74],
    "JXZ-WHITE-02" => [112, 31, 31],
    "JZDJ-WS" => [116, 73, 1],
    "JZDJ-YS" => [138, 95, 1],
    "JZJJ-001" => [242, 159, 42],
    "KJ-207-GD" => [47, 19, 27],
    "KJ-207-GY" => [21, 4, 17],
    "KJ-207-WT" => [45, 5, 40],
    "KJ-217-GD" => [218, 128, 68],
    "KJ-217-WT" => [204, 122, 37],
    "KJ-218-GD" => [5, 5, 0],
    "KJ-218-GY" => [1, 1, 0],
    "KJ-226-GD" => [40, 2, 38],
    "KJ-226-GY" => [20, 1, 19],
    "KJ-226-SV" => [59, 6, 52],
    "KJ-228-BK" => [97, 11, 56],
    "KJ-228-SV" => [139, 26, 55],
    "KJ-228-WT" => [86, 6, 60],
    "LDD001-BK" => [68, 19, 49],
    "LDD002" => [94, 24, 70],
    "LDD003" => [63, 7, 54],
    "LDD004" => [20, 4, 16],
    "LDD005" => [29, 19, 10],
    "XCQ707" => [52, 2, 49],
    "ZJ007" => [0, 0, 0]
  }.freeze

  def initialize(rows: SOURCE_ROWS, apply: ActiveModel::Type::Boolean.new.cast(ENV["APPLY"]))
    @rows = rows
    @apply = apply
  end

  def call
    validate_skus!
    changes = reconciliation_rows
    print_preview(changes)

    unless @apply
      puts "Preview only. Run with APPLY=1 to write #{write_rows(changes).size} adjustment batches."
      return changes
    end

    ApplicationRecord.transaction do
      write_rows(changes).each { |row| persist!(row) }
      verify!
    end

    puts "Applied #{write_rows(changes).size} adjustment batches; all #{@rows.size} SKU gaps are zero."
    changes
  end

  private

  def validate_skus!
    missing = @rows.keys - Ec::Sku.where(sku_code: @rows.keys).pluck(:sku_code)
    raise "Missing SKU(s): #{missing.join(', ')}" if missing.any?
  end

  def reconciliation_rows
    @rows.sort.map do |sku_code, (official, fbs, fbw)|
      target_offset = official - fbs - fbw
      raise "Negative target offset for #{sku_code}: #{target_offset}" if target_offset.negative?

      batch_code = batch_code_for(sku_code)
      other_signed_offset = signed_offset_for(sku_code, excluding: batch_code)
      quantity = -target_offset - other_signed_offset

      {
        sku_code: sku_code,
        batch_code: batch_code,
        official: official,
        fbs: fbs,
        fbw: fbw,
        target_offset: target_offset,
        other_offset: -other_signed_offset,
        quantity: quantity
      }
    end
  end

  def print_preview(rows)
    puts "SKU | official | FBS | FBW | other offset | this batch | final offset | final gap"
    rows.each do |row|
      final_offset = row[:other_offset] - row[:quantity]
      final_gap = row[:official] - row[:fbs] - row[:fbw] - final_offset
      puts [row[:sku_code], row[:official], row[:fbs], row[:fbw], row[:other_offset], row[:quantity], final_offset, final_gap].join(" | ")
    end
  end

  def write_rows(rows)
    rows.select do |row|
      row[:quantity] != 0 || Ec::SkuBatch.exists?(batch_code: row[:batch_code])
    end
  end

  def persist!(row)
    batch = Ec::SkuBatch.find_or_initialize_by(batch_code: row[:batch_code])
    if batch.persisted? && batch.sku_code != row[:sku_code]
      raise "Batch code #{row[:batch_code]} belongs to #{batch.sku_code}"
    end

    batch.assign_attributes(
      sku_code: row[:sku_code],
      batch_type: :wb_fbw_offset,
      status: "closed",
      purchase_date: Date.new(2026, 8, 6),
      received_on: Date.new(2026, 8, 6),
      purchased_quantity: row[:quantity],
      received_quantity: row[:quantity],
      purchase_unit_price_cny: 0,
      defect_offset_note: SOURCE_NOTE,
      memo: "official=#{row[:official]}, fbs=#{row[:fbs]}, fbw=#{row[:fbw]}, target_offset=#{row[:target_offset]}"
    )
    batch.save!
  end

  def verify!
    failures = @rows.filter_map do |sku_code, (official, fbs, fbw)|
      final_offset = -signed_offset_for(sku_code)
      gap = official - fbs - fbw - final_offset
      [sku_code, gap] unless gap.zero?
    end
    raise "Non-zero gap after reconciliation: #{failures.map { |sku, gap| "#{sku}=#{gap}" }.join(', ')}" if failures.any?
  end

  def signed_offset_for(sku_code, excluding: nil)
    scope = Ec::SkuBatch.wb_fbw_offset.where(sku_code: sku_code)
    scope = scope.where.not(batch_code: excluding) if excluding
    scope.sum(Arel.sql(Ec::SkuBatch::EFFECTIVE_RECEIVED_QUANTITY_SQL)).to_i
  end

  def batch_code_for(sku_code)
    "#{BATCH_PREFIX}-#{sku_code}"
  end
end

WbFbwDeliveredOffsetReconciler20260806.new.call unless ENV["SKIP_WB_FBW_RECONCILE_RUN"] == "1"
