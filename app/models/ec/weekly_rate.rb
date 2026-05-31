module Ec
  class WeeklyRate < ApplicationRecord
    self.table_name = 'ec_weekly_rates'

    validates :week_start, presence: true, uniqueness: true
    validates :rate_cny_rub, :rate_byn_rub, presence: true, numericality: { greater_than: 0 }

    # 返回指定自然周（周一日期）的汇率，如无精确匹配则取最近一条过去的记录
    def self.for_week(week_start_date)
      d = week_start_date.to_date
      find_by(week_start: d) ||
        where('week_start <= ?', d).order(week_start: :desc).first
    end

    # 查库 → 查不到则从 CBR 拉取存库 → 若 CBR 失败则用最近一条兜底
    def self.resolve(week_start_date)
      d = week_start_date.to_date
      rec = find_by(week_start: d)
      return rec if rec

      begin
        Ec::CbrRateFetcher.fetch_and_store(date: d)
        rec = find_by(week_start: d)
        return rec if rec
      rescue => e
        puts "[WeeklyRate] CBR 拉取失败（#{d}）: #{e.message}，使用最近一条汇率兜底"
      end

      fallback = where('week_start <= ?', d).order(week_start: :desc).first
      puts "[WeeklyRate] 使用兜底汇率 #{fallback&.week_start}：CNY/RUB=#{fallback&.rate_cny_rub}" if fallback
      fallback
    end
  end
end
