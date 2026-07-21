module Ec
  class WeeklyProfitReportQuery
    include WeeklySummarySupport

    SUMMARY_KEYS = {
      "wb" => %i[total_sales_qty total_return_qty total_net total_goods_cost total_pre_tax total_tax total_after_tax unallocated_rows],
      "ozon" => %i[sku_count total_sales_revenue total_orders total_returns total_ad total_goods_cost total_after_tax_profit unallocated_total]
    }.freeze
    ROW_KEYS = {
      "wb" => %i[sales_qty return_qty net_qty settlement delivery storage ad goods_cost pre_tax tax after_tax],
      "ozon" => %i[sales_revenue commission delivery_charge total_ad_cost order_count net_sales_count blr_count export_count goods_cost pre_tax_profit after_tax_profit after_tax_margin_pct]
    }.freeze

    def self.run(store_ref:, from_date:, to_date:, sku_codes: [])
      new(store_ref:, from_date:, to_date:, sku_codes:).run
    end

    def initialize(store_ref:, from_date:, to_date:, sku_codes: [])
      @store_ref = store_ref.to_s
      @from_date = from_date.to_date
      @to_date = to_date.to_date
      @sku_codes = sku_codes
      @platform, @account_id = parse_store_ref!(@store_ref)
    end

    def run
      account = find_account!
      rate = rate_for(@from_date)
      raise ArgumentError, "missing_weekly_rate" unless rate

      service = build_service(rate).call
      prev_from, prev_to = previous_period_range(@from_date, @to_date)
      previous_rate = rate_for(prev_from)
      previous_service = previous_rate ? build_service(previous_rate, from_date: prev_from, to_date: prev_to).call : nil

      {
        report_type: "wr",
        period: {
          from_date: @from_date.to_s,
          to_date: @to_date.to_s
        },
        comparison: {
          period: {
            from_date: prev_from.to_s,
            to_date: prev_to.to_s
          },
          summary: build_summary_comparison(service.summary, previous_service&.summary, SUMMARY_KEYS.fetch(@platform)),
          rows: build_row_comparison_map(
            service.results,
            previous_service&.results || [],
            key_builder: ->(row) { wr_row_key(row) },
            metric_keys: ROW_KEYS.fetch(@platform)
          ),
          extras: {
            unallocated: build_unallocated_comparison_map(
              wr_unallocated_rows(service.unallocated),
              wr_unallocated_rows(previous_service&.unallocated),
              key_builder: ->(row) { wr_unallocated_row_key(row) }
            )
          }
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

    def build_service(rate, from_date: @from_date, to_date: @to_date)
      case @platform
      when "wb"
        Ec::WbProfitAttribution.new(
          account_id: @account_id,
          from_date: from_date,
          to_date: to_date,
          rate_cny_rub: rate.rate_cny_rub,
          rate_byn_rub: rate.rate_byn_rub,
          sku_codes: @sku_codes
        )
      when "ozon"
        Ec::OzonProfitAttribution.new(
          account_id: @account_id,
          from_date: from_date,
          to_date: to_date,
          rate_cny_rub: rate.rate_cny_rub,
          sync_missing_ad_costs: false,
          sku_codes: @sku_codes
        )
      end
    end

    def rate_for(date)
      Ec::WeeklyRate.find_by(week_start: date.beginning_of_week(:monday))
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

    def wr_row_key(row)
      case @platform
      when "wb"
        row[:vendor_code].presence || row[:nm_id].to_s
      when "ozon"
        row[:sku_code].presence || row[:ozon_sku_id].to_s
      end
    end

    def wr_unallocated_rows(unallocated)
      unallocated ||= {}
      if @platform == "ozon"
        WeeklyProfitReports::OzonUnallocatedRows.normalize(unallocated)
      else
        unallocated.map { |name, amount| { name: name, amount: amount } }
      end
    end

    def wr_unallocated_row_key(row)
      if @platform == "ozon"
        row[:type_id]
      else
        row[:name].to_s
      end
    end
  end
end
