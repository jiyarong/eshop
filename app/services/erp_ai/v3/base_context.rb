module ErpAI
  module V3
    class BaseContext
      SALES_HISTORY_WEEKS = 12

      def initialize(sku:, period_to:, profit_query: Ec::SkuProfitPeriodSeriesQuery)
        @sku = sku
        @period_to = period_to.to_date
        @profit_query = profit_query
      end

      def call
        marketing_state = sku.current_marketing_state

        {
          spu_code: sku.master_sku&.master_sku_code,
          spu_id: sku.master_sku_id,
          related_spu_sku_codes: related_spu_sku_codes,
          current_stage: marketing_state&.stage&.upcase,
          current_grade: marketing_state&.grade,
          sales_amount_last_3_months: sales_amount_last_3_months,
          sku_products: sku.sku_products.order(:id).map do |sku_product|
            {
              store_id: sku_product.store_id,
              platform: sku_product.platform,
              product_id: sku_product.product_id,
              offer_id: sku_product.offer_id
            }
          end
        }
      end

      private

      attr_reader :sku, :period_to, :profit_query

      def related_spu_sku_codes
        return [] unless sku.master_sku

        sku.master_sku.skus.filter_map do |related_sku|
          related_sku.sku_code unless related_sku.id == sku.id
        end.sort
      end

      def sales_amount_last_3_months
        periods = SALES_HISTORY_WEEKS.times.map do |offset|
          week_start = latest_week_start - (SALES_HISTORY_WEEKS - offset - 1).weeks
          {
            key: week_start.iso8601,
            from_date: week_start,
            to_date: week_start.end_of_week(:monday)
          }
        end
        report = profit_query.run(sku: sku, periods: periods)
        sales_by_week = report.index_by { |period| period.fetch(:from_date).to_date }

        periods.to_h do |period|
          week_start = period.fetch(:from_date)
          [period.fetch(:key), sales_by_week.dig(week_start, :sku_row, :net_sales).to_i]
        end
      end

      def latest_week_start
        period_to.beginning_of_week(:monday)
      end
    end
  end
end
