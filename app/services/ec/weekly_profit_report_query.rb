module Ec
  class WeeklyProfitReportQuery
    def self.run(store_ref:, from_date:, to_date:)
      new(store_ref:, from_date:, to_date:).run
    end

    def initialize(store_ref:, from_date:, to_date:)
      @store_ref = store_ref.to_s
      @from_date = from_date.to_date
      @to_date = to_date.to_date
      @platform, @account_id = parse_store_ref!(@store_ref)
    end

    def run
      account = find_account!
      rate = Ec::WeeklyRate.find_by(week_start: @from_date.beginning_of_week(:monday))
      raise ArgumentError, "missing_weekly_rate" unless rate

      service = build_service(rate).call

      {
        report_type: "wr",
        period: {
          from_date: @from_date.to_s,
          to_date: @to_date.to_s
        },
        meta: {
          platform: @platform,
          account: account_payload(account),
          rates: rate_payload(rate)
        },
        summary: service.summary,
        rows: service.results,
        extras: {
          unallocated: service.unallocated
        }
      }
    end

    private

    def parse_store_ref!(value)
      platform, raw_id = value.split(":", 2)
      raise ArgumentError, "invalid_store_ref" unless %w[wb ozon].include?(platform) && raw_id.present?

      [platform, Integer(raw_id)]
    rescue ArgumentError
      raise ArgumentError, "invalid_store_ref"
    end

    def find_account!
      case @platform
      when "wb"
        RawWb::SellerAccount.where(is_active: true).find(@account_id)
      when "ozon"
        RawOzon::SellerAccount.where(is_active: true).find(@account_id)
      end
    end

    def build_service(rate)
      case @platform
      when "wb"
        Ec::WbProfitAttribution.new(
          account_id: @account_id,
          from_date: @from_date,
          to_date: @to_date,
          rate_cny_rub: rate.rate_cny_rub,
          rate_byn_rub: rate.rate_byn_rub
        )
      when "ozon"
        Ec::OzonProfitAttribution.new(
          account_id: @account_id,
          from_date: @from_date,
          to_date: @to_date,
          rate_cny_rub: rate.rate_cny_rub,
          sync_missing_ad_costs: false
        )
      end
    end

    def account_payload(account)
      {
        id: account.id,
        name: @platform == "wb" ? account.name : account.company_name
      }
    end

    def rate_payload(rate)
      payload = { rate_cny_rub: rate.rate_cny_rub }
      payload[:rate_byn_rub] = rate.rate_byn_rub if @platform == "wb"
      payload
    end
  end
end
