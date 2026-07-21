# frozen_string_literal: true

require "set"

# 用法:
#   DRY_RUN=1 bundle exec rails runner script/refresh_sku_quality_grades_from_wsu_deep.rb
#   bundle exec rails runner script/refresh_sku_quality_grades_from_wsu_deep.rb
#   FROM_DATE=2026-07-06 TO_DATE=2026-07-12 bundle exec rails runner script/refresh_sku_quality_grades_from_wsu_deep.rb
#
# 纠偏逻辑:
#   1. 删除上次 WSU-DEEP 脚本生成的当前 MarketingState，避免把 Stage 默认成 mat。
#   2. 按 SKU Grade 规则刷新 ec_skus.quality_grade。
#   3. ROI 口径使用 WSU-DEEP 的「年化(按180天备货)」列 annualized_return_pct。

class WsuDeepQualityGradeRefresh
  DEFAULT_TIME_ZONE = "Asia/Shanghai"
  GENERATED_NOTE_PREFIX = "WSU-DEEP自动刷新Grade"
  PROFIT_THRESHOLDS = {
    "S" => BigDecimal("250000"),
    "A" => BigDecimal("100000"),
    "B" => BigDecimal("40000")
  }.freeze
  ANNUALIZED_RETURN_THRESHOLDS = {
    "S" => BigDecimal("100"),
    "A" => BigDecimal("80"),
    "B" => BigDecimal("60")
  }.freeze

  Result = Struct.new(:updated, :unchanged, :skipped, :cleared_marketing_states, keyword_init: true)

  def initialize(env: ENV, stdout: $stdout)
    @env = env
    @stdout = stdout
    @dry_run = ActiveModel::Type::Boolean.new.cast(env.fetch("DRY_RUN", false))
    @allow_rate_sync = ActiveModel::Type::Boolean.new.cast(env.fetch("ALLOW_RATE_SYNC", false))
    @clear_marketing_states = ActiveModel::Type::Boolean.new.cast(env.fetch("CLEAR_MARKETING_STATES", true))
    @from_date = parse_date(env["FROM_DATE"])
    @to_date = parse_date(env["TO_DATE"])
    @sku_codes = parse_sku_codes(env["SKU_CODES"])
  end

  def call
    validate!

    stdout.puts "WSU-DEEP Quality Grade refresh"
    stdout.puts "Period: #{from_date} ~ #{to_date}"
    stdout.puts "Dry run: #{dry_run ? "yes" : "no"}"
    stdout.puts "Allow rate sync: #{allow_rate_sync ? "yes" : "no"}"
    stdout.puts "Clear generated marketing states: #{clear_marketing_states ? "yes" : "no"}"
    stdout.puts "SKU filter: #{sku_codes.any? ? sku_codes.join(", ") : "all"}"

    result = Result.new(updated: 0, unchanged: 0, skipped: 0, cleared_marketing_states: 0)
    result.cleared_marketing_states = clear_generated_marketing_states if clear_marketing_states

    rows = filtered_rows
    stdout.puts "WSU-DEEP rows: #{rows.size}"

    rows.each { |row| apply_row(row, result) }

    stdout.puts "Cleared marketing states: #{result.cleared_marketing_states}"
    stdout.puts "Updated quality grades: #{result.updated}"
    stdout.puts "Unchanged quality grades: #{result.unchanged}"
    stdout.puts "Skipped: #{result.skipped}"
    stdout.puts "DRY_RUN=1, no data changed." if dry_run
    result
  end

  private

  attr_reader :env, :stdout, :dry_run, :allow_rate_sync, :clear_marketing_states, :from_date, :to_date, :sku_codes

  def validate!
    raise ArgumentError, "FROM_DATE must be <= TO_DATE" if from_date > to_date
  end

  def clear_generated_marketing_states
    scope = Ec::SkuMarketingState.current.where("note LIKE ?", "#{GENERATED_NOTE_PREFIX}%")
    count = scope.count
    stdout.puts "#{dry_run ? "DRY" : "DELETE"} generated current marketing states: #{count}"
    return count if dry_run || count.zero?

    ids = scope.pluck(:id)
    Ec::OperationLog.where(record_type: "Ec::SkuMarketingState", record_id: ids).delete_all
    Ec::SkuMarketingState.where(id: ids).delete_all
    count
  end

  def filtered_rows
    rows = wsu_deep_payload.fetch(:rows)
    return rows if sku_codes.empty?

    wanted = sku_codes.to_set
    rows.select { |row| wanted.include?(row.fetch(:sku).to_s.upcase) }
  end

  def wsu_deep_payload
    return Ec::WeeklySummaryDeepQuery.run(from_date: from_date, to_date: to_date) if allow_rate_sync

    rate = Ec::WeeklyRate.for_week(from_date)
    unless rate
      raise "找不到 #{from_date} 或更早的汇率；请先录入 ec_weekly_rates，或显式设置 ALLOW_RATE_SYNC=1 允许自动拉取汇率"
    end

    query = Ec::WeeklySummaryDeepQuery.new(from_date: from_date, to_date: to_date, rate: rate)
    query.define_singleton_method(:previous_rows_data) { [[], nil, nil] }
    query.run
  end

  def apply_row(row, result)
    sku_code = row.fetch(:sku).to_s.upcase
    sku = Ec::Sku.find_by(sku_code: sku_code)
    unless sku
      stdout.puts "SKIP #{sku_code}: SKU not found"
      result.skipped += 1
      return
    end

    grade = grade_for(row)
    if sku.quality_grade == grade
      stdout.puts "UNCHANGED #{sku_code}: quality_grade #{grade}, #{metric_label(row)}"
      result.unchanged += 1
      return
    end

    stdout.puts "#{dry_run ? "DRY" : "UPDATE"} #{sku_code}: quality_grade #{sku.quality_grade || "-"} -> #{grade}, #{metric_label(row)}"
    result.updated += 1
    sku.update!(quality_grade: grade) unless dry_run
  end

  def grade_for(row)
    annualized_net_profit = decimal_or_zero(row[:annualized_net_profit_cny])
    annualized_return_pct = decimal_or_zero(row[:annualized_return_pct])

    return "S" if annualized_net_profit > PROFIT_THRESHOLDS.fetch("S") && annualized_return_pct > ANNUALIZED_RETURN_THRESHOLDS.fetch("S")
    return "A" if annualized_net_profit >= PROFIT_THRESHOLDS.fetch("A") && annualized_return_pct > ANNUALIZED_RETURN_THRESHOLDS.fetch("A")
    return "B" if annualized_net_profit >= PROFIT_THRESHOLDS.fetch("B") && annualized_return_pct > ANNUALIZED_RETURN_THRESHOLDS.fetch("B")

    "C"
  end

  def metric_label(row)
    [
      "年化净利=#{format_decimal(row[:annualized_net_profit_cny])}",
      "年化回报率=#{format_decimal(row[:annualized_return_pct])}%",
      "180天ROI=#{format_decimal(row[:projected_roi_pct])}%",
      "净销量=#{row[:net_sales]}"
    ].join("，")
  end

  def format_decimal(value)
    return "N/A" if value.blank?

    BigDecimal(value.to_s).round(2).to_s("F")
  end

  def decimal_or_zero(value)
    return BigDecimal("0") if value.blank?

    BigDecimal(value.to_s)
  end

  def parse_sku_codes(value)
    value.to_s.split(",").map { |sku| sku.strip.upcase }.reject(&:blank?).uniq
  end

  def parse_date(value)
    return Date.parse(value) if value.present?

    last_completed_week_start
  end

  def last_completed_week_start
    today = Time.find_zone!(DEFAULT_TIME_ZONE).today
    today.beginning_of_week(:monday) - 7.days
  end
end

unless ENV["SKIP_WSU_DEEP_QUALITY_GRADE_REFRESH_AUTORUN"] == "1"
  refresher = WsuDeepQualityGradeRefresh.new

  if ENV["TO_DATE"].blank?
    from_date = refresher.send(:from_date)
    to_date = from_date + 6.days
    refresher = WsuDeepQualityGradeRefresh.new(env: ENV.to_h.merge("FROM_DATE" => from_date.to_s, "TO_DATE" => to_date.to_s))
  end

  refresher.call
end
