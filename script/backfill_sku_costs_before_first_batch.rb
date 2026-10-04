# frozen_string_literal: true

# 为首个业务批次早于首条成本生效日的 SKU 补一条历史成本。
# 默认仅预览；设置 APPLY=1 后写入。
#
# Usage:
#   bin/rails runner script/backfill_sku_costs_before_first_batch.rb
#   APPLY=1 bin/rails runner script/backfill_sku_costs_before_first_batch.rb

class SkuCostsBeforeFirstBatchBackfill
  INCOMING_STATUSES = Ec::InventoryCapitalDistributionQuery::INCOMING_STATUSES
  BOOK_STATUSES = Ec::InventoryCapitalDistributionQuery::BOOK_STATUSES
  Result = Struct.new(:scanned, :backfilled, :covered, :missing_cost, keyword_init: true)

  def initialize(env: ENV, stdout: $stdout, sku_codes: nil)
    @dry_run = !ActiveModel::Type::Boolean.new.cast(env.fetch("APPLY", false))
    @stdout = stdout
    @sku_codes = Array(sku_codes).presence
  end

  def call
    first_batch_dates = first_report_batch_dates
    result = Result.new(scanned: first_batch_dates.size, backfilled: 0, covered: 0, missing_cost: 0)

    stdout.puts "SKU costs before first batch backfill (#{dry_run ? 'dry run' : 'apply'})"
    stdout.puts "SKUs with business batches: #{result.scanned}"

    first_batch_dates.sort.each do |sku_code, first_batch_on|
      process_sku(sku_code, first_batch_on, result)
    end

    stdout.puts "Backfilled: #{result.backfilled}"
    stdout.puts "Already covered: #{result.covered}"
    stdout.puts "Missing any cost (skipped): #{result.missing_cost}"
    stdout.puts "No data changed. Set APPLY=1 to write." if dry_run
    result
  end

  private

  attr_reader :dry_run, :sku_codes, :stdout

  def first_report_batch_dates
    scope = Ec::SkuBatch
      .where.not(batch_type: :physical_stocktake_adjustment)
      .where(status: INCOMING_STATUSES + BOOK_STATUSES)
    scope = scope.where(sku_code: sku_codes) if sku_codes

    scope.pluck(:sku_code, :batch_type, :status, :purchase_date, :received_on, :created_at)
      .each_with_object({}) do |(sku_code, batch_type, status, purchase_date, received_on, created_at), dates|
        next if status.in?(INCOMING_STATUSES) && batch_type != "normal"

        cost_date = purchase_date || received_on || created_at&.to_date || Date.current
        dates[sku_code] = [ dates[sku_code], cost_date ].compact.min
      end
  end

  def process_sku(sku_code, first_batch_on, result)
    sku = Ec::Sku.find_by(sku_code: sku_code)
    return unless sku

    sku.with_lock do
      source_cost = Ec::SkuCost.where(sku_code: sku_code).order(:effective_on, :id).first
      unless source_cost
        result.missing_cost += 1
        stdout.puts "SKIP #{sku_code}: no SKU cost"
        next
      end

      if source_cost.effective_on <= first_batch_on
        result.covered += 1
        next
      end

      target_effective_on = first_batch_on - 1.day
      copied_cost = source_cost.dup
      copied_cost.effective_on = target_effective_on
      copied_cost.save! unless dry_run

      prefix = dry_run ? "DRY[COPY]" : "COPY"
      stdout.puts "#{prefix} #{sku_code} first_batch_on=#{first_batch_on} " \
                  "source_effective_on=#{source_cost.effective_on} target_effective_on=#{target_effective_on}"
      result.backfilled += 1
    end
  end
end

if $PROGRAM_NAME == __FILE__
  SkuCostsBeforeFirstBatchBackfill.new.call
end
