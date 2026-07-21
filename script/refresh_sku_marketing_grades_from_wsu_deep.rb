# frozen_string_literal: true

require "set"

# 用法:
#   bundle exec rails runner script/refresh_sku_marketing_grades_from_wsu_deep.rb
#   DRY_RUN=1 bundle exec rails runner script/refresh_sku_marketing_grades_from_wsu_deep.rb
#   FROM_DATE=2026-07-06 TO_DATE=2026-07-12 bundle exec rails runner script/refresh_sku_marketing_grades_from_wsu_deep.rb
#   SKU_CODES=SKU1,SKU2 USER_EMAIL=manager@example.com bundle exec rails runner script/refresh_sku_marketing_grades_from_wsu_deep.rb
#   ALLOW_RATE_SYNC=1 bundle exec rails runner script/refresh_sku_marketing_grades_from_wsu_deep.rb
#
# 规则来自 SKU Grade 表:
#   S: 年化净利 > 250,000 且 年化回报率 > 100%
#   A: 年化净利 >= 100,000 且 年化回报率 > 80%
#   B: 年化净利 >= 40,000 且 年化回报率 > 60%
#   C: 其余情况
#
# 脚本只刷新 Marketing Grade，Stage 会沿用当前营销状态；没有当前状态时使用 DEFAULT_STAGE，默认 mat。

class WsuDeepMarketingGradeRefresh
  DEFAULT_TIME_ZONE = "Asia/Shanghai"
  DEFAULT_STAGE = "mat"
  PROFIT_THRESHOLDS = {
    "S" => BigDecimal("250000"),
    "A" => BigDecimal("100000"),
    "B" => BigDecimal("40000")
  }.freeze
  ROI_THRESHOLDS = {
    "S" => BigDecimal("100"),
    "A" => BigDecimal("80"),
    "B" => BigDecimal("60")
  }.freeze

  Result = Struct.new(:updated, :unchanged, :skipped, keyword_init: true)

  def initialize(env: ENV, stdout: $stdout)
    @env = env
    @stdout = stdout
    @dry_run = ActiveModel::Type::Boolean.new.cast(env.fetch("DRY_RUN", false))
    @allow_rate_sync = ActiveModel::Type::Boolean.new.cast(env.fetch("ALLOW_RATE_SYNC", false))
    @from_date = parse_date(env["FROM_DATE"])
    @to_date = parse_date(env["TO_DATE"])
    @default_stage = env.fetch("DEFAULT_STAGE", DEFAULT_STAGE).to_s.downcase
    @sku_codes = parse_sku_codes(env["SKU_CODES"])
    @changed_by = find_user(env["USER_EMAIL"])
  end

  def call
    validate!
    Current.user = changed_by

    stdout.puts "WSU-DEEP Grade refresh"
    stdout.puts "Period: #{from_date} ~ #{to_date}"
    stdout.puts "Dry run: #{dry_run ? "yes" : "no"}"
    stdout.puts "Allow rate sync: #{allow_rate_sync ? "yes" : "no"}"
    stdout.puts "Default stage for unset SKU: #{default_stage}"
    stdout.puts "SKU filter: #{sku_codes.any? ? sku_codes.join(", ") : "all"}"
    stdout.puts "Changed by: #{changed_by&.display_name || "system"}"

    rows = filtered_rows
    stdout.puts "WSU-DEEP rows: #{rows.size}"

    result = rows.each_with_object(Result.new(updated: 0, unchanged: 0, skipped: 0)) do |row, summary|
      apply_row(row, summary)
    end

    stdout.puts "Updated: #{result.updated}"
    stdout.puts "Unchanged: #{result.unchanged}"
    stdout.puts "Skipped: #{result.skipped}"
    stdout.puts "DRY_RUN=1, no data changed." if dry_run
    result
  ensure
    Current.user = nil
  end

  private

  attr_reader :env, :stdout, :dry_run, :allow_rate_sync, :from_date, :to_date, :default_stage, :sku_codes, :changed_by

  def validate!
    unless Ec::SkuMarketingState::STAGES.include?(default_stage)
      raise ArgumentError, "DEFAULT_STAGE must be one of: #{Ec::SkuMarketingState::STAGES.join(", ")}"
    end

    raise ArgumentError, "FROM_DATE must be <= TO_DATE" if from_date > to_date
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

  def apply_row(row, summary)
    sku_code = row.fetch(:sku).to_s.upcase
    sku = Ec::Sku.includes(:current_marketing_state).find_by(sku_code: sku_code)
    unless sku
      stdout.puts "SKIP #{sku_code}: SKU not found"
      summary.skipped += 1
      return
    end

    grade = grade_for(row)
    current_state = sku.current_marketing_state
    stage = current_state&.stage || default_stage
    current_grade = current_state&.grade

    if current_grade == grade
      stdout.puts "UNCHANGED #{sku_code}: Grade #{grade}, Stage #{stage}, #{metric_label(row)}"
      summary.unchanged += 1
      return
    end

    stdout.puts "#{dry_run ? "DRY" : "UPDATE"} #{sku_code}: #{current_grade || "-"} -> #{grade}, Stage #{stage}, #{metric_label(row)}"
    summary.updated += 1
    return if dry_run

    Ec::SkuMarketingStateChange.new(
      sku: sku,
      grade: grade,
      stage: stage,
      changed_by: changed_by,
      note: note_for(row)
    ).call
  end

  def grade_for(row)
    annualized_net_profit = decimal_or_zero(row[:annualized_net_profit_cny])
    annualized_return_pct = decimal_or_zero(row[:annualized_return_pct])

    return "S" if annualized_net_profit > PROFIT_THRESHOLDS.fetch("S") && annualized_return_pct > ROI_THRESHOLDS.fetch("S")
    return "A" if annualized_net_profit >= PROFIT_THRESHOLDS.fetch("A") && annualized_return_pct > ROI_THRESHOLDS.fetch("A")
    return "B" if annualized_net_profit >= PROFIT_THRESHOLDS.fetch("B") && annualized_return_pct > ROI_THRESHOLDS.fetch("B")

    "C"
  end

  def note_for(row)
    "WSU-DEEP自动刷新Grade，周期 #{from_date}~#{to_date}，#{metric_label(row)}"
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

  def find_user(email)
    return nil if email.blank?

    User.find_by!(email: email)
  end

  def parse_date(value)
    return Date.parse(value) if value.present?

    last_completed_week_start
  end

  def last_completed_week_start
    today = Time.find_zone!(DEFAULT_TIME_ZONE).today
    this_week_start = today.beginning_of_week(:monday)

    if env["FROM_DATE"].blank?
      this_week_start - 7.days
    else
      this_week_start - 1.day
    end
  end
end

unless ENV["SKIP_WSU_DEEP_GRADE_REFRESH_AUTORUN"] == "1"
  refresher = WsuDeepMarketingGradeRefresh.new

  if ENV["TO_DATE"].blank?
    from_date = refresher.send(:from_date)
    to_date = from_date + 6.days
    refresher = WsuDeepMarketingGradeRefresh.new(env: ENV.to_h.merge("FROM_DATE" => from_date.to_s, "TO_DATE" => to_date.to_s))
  end

  refresher.call
end
