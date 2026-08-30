module ErpAI
  module V2
    class MarketingProfitabilityContext
      def initialize(
        sku:,
        channels:,
        period_from:,
        period_to:,
        today:,
        profit_query: Ec::WeeklyProfitReportQuery
      )
        @sku = sku
        @channels = Array(channels).filter_map { |channel| indifferent_hash(channel) }
          .select { |channel| channel[:account_ref].present? }
        @period_from = period_from.to_date
        @period_to = period_to.to_date
        @today = today.to_date
        @profit_query = profit_query
      end

      def call
        {
          currency: "CNY",
          weekly: weekly_periods.map { |period| week_payload(period) }
        }
      end

      private

      attr_reader :sku, :channels, :period_from, :period_to, :today, :profit_query

      def week_payload(period)
        payload = period_payload(period).merge(is_partial: period.fetch(:period_to) >= today)
        return payload.merge(data_status: "partial_week") if payload.fetch(:is_partial)
        return payload.merge(data_status: "unavailable", reason: "no_active_bound_store") if channels.empty?

        rate = Ec::WeeklyRate.find_by(week_start: period.fetch(:period_from))
        return payload.merge(data_status: "unavailable", reason: "missing_exchange_rate") unless rate

        store_metrics = []
        unavailable_store_ids = []
        channels.each do |channel|
          report = profit_query.run(
            store_ref: channel.fetch(:account_ref),
            from_date: period.fetch(:period_from),
            to_date: period.fetch(:period_to),
            sku_codes: [ sku.sku_code ],
            include_comparison: false
          )
          metrics = normalized_store_metrics(channel.fetch(:platform), report)
          store_metrics << metrics if metrics
        rescue ActiveRecord::RecordNotFound, ArgumentError, KeyError, TypeError
          unavailable_store_ids << channel.fetch(:store_id)
        end

        return payload.merge(data_status: "no_records", source_store_count: channels.size) if store_metrics.empty? && unavailable_store_ids.empty?
        return payload.merge(
          data_status: "unavailable",
          reason: "profit_sources_unavailable",
          unavailable_store_ids: unavailable_store_ids
        ) if store_metrics.empty?

        payload.merge(
          data_status: unavailable_store_ids.empty? ? "available" : "partial_sources",
          exchange_rate_week: rate.week_start.iso8601,
          source_store_count: store_metrics.size,
          unavailable_store_ids: unavailable_store_ids,
          **aggregate_metrics(store_metrics)
        )
      end

      def normalized_store_metrics(platform, report)
        report = indifferent_hash(report) || {}.with_indifferent_access
        rows = Array(report[:rows]).filter_map do |row|
          indifferent_hash(row)
        end
        return if rows.empty?

        rates = indifferent_hash(report.dig(:meta, :rates)) || {}.with_indifferent_access
        factor = if platform == "wb"
          rate_byn_rub = rates.fetch(:rate_byn_rub).to_d
          rate_cny_rub = rates.fetch(:rate_cny_rub).to_d
          raise ArgumentError, "invalid_exchange_rate" if rate_byn_rub <= 0 || rate_cny_rub <= 0

          rate_byn_rub / rate_cny_rub
        else
          rate_cny_rub = rates.fetch(:rate_cny_rub).to_d
          raise ArgumentError, "invalid_exchange_rate" if rate_cny_rub <= 0

          1.to_d / rate_cny_rub
        end

        platform == "wb" ? normalize_wb(rows, factor) : normalize_ozon(rows, factor)
      end

      def normalize_wb(rows, factor)
        {
          net_sales: sum_rows(rows, :net_qty),
          revenue: converted_sum(rows, :settlement, factor),
          ads: converted_sum(rows, :ad, factor),
          goods_cost: converted_sum(rows, :goods_cost, factor),
          pre_tax: converted_sum(rows, :pre_tax, factor),
          tax: converted_sum(rows, :tax, factor),
          after_tax: converted_sum(rows, :after_tax, factor)
        }
      end

      def normalize_ozon(rows, factor)
        pre_tax = converted_sum(rows, :pre_tax_profit, factor)
        after_tax = converted_sum(rows, :after_tax_profit, factor)

        {
          net_sales: sum_rows(rows, :net_sales_count),
          revenue: converted_sum(rows, :sales_revenue, factor),
          ads: negate(converted_sum(rows, :total_ad_cost, factor)),
          goods_cost: negate(converted_sum(rows, :goods_cost, factor)),
          pre_tax: pre_tax,
          tax: pre_tax.nil? || after_tax.nil? ? nil : round_number(pre_tax - after_tax),
          after_tax: after_tax
        }
      end

      def aggregate_metrics(store_metrics)
        net_sales = aggregate_metric(store_metrics, :net_sales)
        revenue = aggregate_metric(store_metrics, :revenue)
        ads = aggregate_metric(store_metrics, :ads)
        goods_cost = aggregate_metric(store_metrics, :goods_cost)
        pre_tax = aggregate_metric(store_metrics, :pre_tax)
        tax = aggregate_metric(store_metrics, :tax)
        after_tax = aggregate_metric(store_metrics, :after_tax)

        {
          net_sales: net_sales,
          revenue: revenue,
          ads: ads,
          goods_cost: goods_cost,
          pre_tax: pre_tax,
          tax: tax,
          after_tax: after_tax,
          margin_pct: percentage(after_tax, revenue),
          average_profit_per_order: ratio(after_tax, net_sales),
          ad_ratio_pct: percentage(ads, revenue),
          cost_return_pct: percentage(after_tax, goods_cost)
        }
      end

      def aggregate_metric(rows, key)
        values = rows.map { |row| row[key] }
        return if values.any?(&:nil?)

        round_number(values.sum(&:to_d))
      end

      def converted_sum(rows, key, factor, default: nil)
        value = sum_rows(rows, key, default: default)
        value.nil? ? nil : round_number(value.to_d * factor)
      end

      def sum_rows(rows, key, default: nil)
        raw_values = rows.map { |row| row[key] }
        return default if raw_values.empty?
        return nil if default.nil? && raw_values.any?(&:nil?)

        values = raw_values.filter_map { |value| value&.to_d }
        return default if values.empty?

        values.sum
      end

      def negate(value)
        value.nil? ? nil : round_number(-value.to_d)
      end

      def percentage(numerator, denominator)
        return if numerator.nil? || denominator.to_d.zero?

        round_number(numerator.to_d / denominator.to_d * 100)
      end

      def ratio(numerator, denominator)
        return if numerator.nil? || denominator.to_d.zero?

        round_number(numerator.to_d / denominator.to_d)
      end

      def round_number(value)
        decimal = value.to_d.round(2)
        decimal.frac.zero? ? decimal.to_i : decimal
      end

      def weekly_periods
        (period_from..period_to).step(7).map do |week_start|
          { period_from: week_start, period_to: week_start.end_of_week(:monday) }
        end
      end

      def period_payload(period)
        {
          period_from: period.fetch(:period_from).iso8601,
          period_to: period.fetch(:period_to).iso8601
        }
      end

      def indifferent_hash(value)
        return value.with_indifferent_access if value.is_a?(Hash)
        return unless value.respond_to?(:to_h)

        converted = value.to_h
        converted.is_a?(Hash) ? converted.with_indifferent_access : nil
      rescue TypeError
        nil
      end
    end
  end
end
