module Ec
  # 从俄罗斯央行（CBR）XML 接口拉取当日或指定日期的汇率，存入 ec_weekly_rates。
  #
  # 用法：
  #   # 拉取本周一的汇率并存库
  #   Ec::CbrRateFetcher.fetch_and_store
  #
  #   # 拉取指定日期（取当天或最近交易日）
  #   Ec::CbrRateFetcher.fetch_and_store(date: Date.new(2026, 5, 5))
  #
  #   # 只查询不存库，返回 { cny_rub:, byn_rub:, date: }
  #   Ec::CbrRateFetcher.fetch(date: Date.current)
  class CbrRateFetcher
    CBR_URL = 'https://www.cbr.ru/scripts/XML_daily.asp'.freeze

    def self.fetch(date: Date.current)
      new(date).fetch
    end

    def self.fetch_and_store(date: nil)
      week_start = date ? date.to_date.beginning_of_week : Date.current.beginning_of_week
      rates = new(week_start).fetch

      Ec::WeeklyRate.upsert(
        { week_start: week_start, rate_cny_rub: rates[:cny_rub], rate_byn_rub: rates[:byn_rub] },
        unique_by: :index_ec_weekly_rates_on_week_start
      )

      ts = Time.current.strftime("%m-%d %H:%M:%S")
      puts "[CbrRate] #{ts} ✓ 汇率已存入 #{week_start}：CNY/RUB=#{rates[:cny_rub]}，BYN/RUB=#{rates[:byn_rub]}"
      rates
    end

    def initialize(date)
      @date = date.to_date
    end

    def fetch
      xml = request_xml
      parse(xml)
    end

    private

    def request_xml
      uri     = URI(CBR_URL)
      uri.query = URI.encode_www_form(date_req: @date.strftime('%d/%m/%Y'))

      retries = 0
      begin
        Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 15) do |http|
          resp = http.get("#{uri.path}?#{uri.query}")
          raise "CBR HTTP #{resp.code}" unless resp.is_a?(Net::HTTPSuccess)
          resp.body.force_encoding('Windows-1251').encode('UTF-8')
        end
      rescue => e
        retries += 1
        raise if retries >= 3
        sleep retries * 5
        retry
      end
    end

    def parse(xml)
      rates = {}

      xml.scan(/<Valute\b[^>]*>(.*?)<\/Valute>/m).each do |block|
        content = block.first
        code    = content[/<CharCode>(.*?)<\/CharCode>/, 1]
        next unless %w[CNY BYN].include?(code)
        nominal = content[/<Nominal>(.*?)<\/Nominal>/, 1].to_i
        value   = content[/<Value>(.*?)<\/Value>/, 1]&.gsub(',', '.').to_f
        next if nominal.zero?
        rates[code] = (value / nominal).round(4)
      end

      raise "CBR 响应缺少 CNY 汇率（日期=#{@date}）" unless rates['CNY']
      raise "CBR 响应缺少 BYN 汇率（日期=#{@date}）" unless rates['BYN']

      { cny_rub: rates['CNY'], byn_rub: rates['BYN'], date: @date }
    end
  end
end
