module ErpAI
  module V2
    class AdvertisingContext
      COUNT_METRICS = %i[impressions clicks cart_additions orders ordered_units canceled modeled_orders].freeze
      MONEY_METRICS = %i[spend attributed_revenue modeled_revenue].freeze
      MONEY_DERIVED_METRICS = %i[avg_cpc cpo drr_pct roas].freeze
      OZON_CPC_MODELS = %w[cpc cpc_history].freeze

      def initialize(
        sku:,
        period_from:,
        period_to:,
        today: Date.current,
        store_ids: nil,
        partial_on_today: false,
        strict_nulls: false
      )
        @sku = sku
        @period_from = period_from
        @period_to = period_to
        @today = today.to_date
        @store_ids = store_ids&.map(&:to_i)&.uniq
        @partial_on_today = partial_on_today
        @strict_nulls = strict_nulls
      end

      def call
        weekly_periods.map do |period|
          period.merge(
            is_partial: period_partial?(period),
            stores: store_groups.map { |group| store_payload(group, period) }
          ).merge(
            period_from: period.fetch(:period_from).iso8601,
            period_to: period.fetch(:period_to).iso8601
          )
        end
      end

      private

      attr_reader :sku, :period_from, :period_to, :today, :store_ids, :partial_on_today, :strict_nulls

      def weekly_periods
        (period_from..period_to).step(7).map do |week_start|
          { period_from: week_start, period_to: week_start.end_of_week(:monday) }
        end
      end

      def period_partial?(period)
        period.fetch(:period_to) > today || (partial_on_today && period.fetch(:period_to) == today)
      end

      def store_groups
        @store_groups ||= filtered_sku_products.group_by { |product| [ product.platform, product.store ] }
          .filter_map do |(platform, store), products|
            account_id = platform == "wb" ? store.wb_raw_account_id : store.ozon_raw_account_id
            next if account_id.blank?

            { platform:, store:, account_id:, products: }
          end
          .sort_by { |group| [ group.fetch(:platform), group.fetch(:store).id ] }
      end

      def filtered_sku_products
        scope = sku.sku_products.includes(:store)
        store_ids.nil? ? scope : scope.where(store_id: store_ids)
      end

      def store_payload(group, period)
        rows = group.fetch(:platform) == "wb" ? wb_rows(group, period) : ozon_rows(group, period)
        dates = rows.filter_map { |row| row[:data_through] }
        {
          store_ref: "#{group.fetch(:platform)}:#{group.fetch(:account_id)}",
          platform: group.fetch(:platform),
          store_id: group.fetch(:store).id,
          store_name: group.fetch(:store).store_name,
          data_status: rows.any? { |row| row[:data_status] == "available" } ? "available" : "no_records",
          days_with_data: rows.flat_map { |row| row[:data_dates] }.uniq.size,
          data_through: dates.max&.iso8601,
          data: rows.map do |row|
            row.except(:data_dates).merge(data_through: row[:data_through]&.iso8601)
          end
        }
      rescue ActiveRecord::RecordNotFound, ArgumentError, KeyError, TypeError
        source_payload(group).merge(
          data_status: "unavailable",
          days_with_data: 0,
          data_through: nil,
          data: [],
          reason: "source_unavailable"
        )
      end

      def source_payload(group)
        {
          store_ref: "#{group.fetch(:platform)}:#{group.fetch(:account_id)}",
          platform: group.fetch(:platform),
          store_id: group.fetch(:store).id,
          store_name: group.fetch(:store).store_name
        }
      end

      def wb_rows(group, period)
        product_ids = group.fetch(:products).filter_map { |product| positive_integer(product.product_id) }.uniq
        records = RawWb::AdvProductDailyStat.all_apps.joins(:campaign).where(
          raw_wb_adv_campaigns: { store_id: group.fetch(:store).id },
          nm_id: product_ids,
          stat_date: period.fetch(:period_from)..period.fetch(:period_to)
        ).to_a.group_by(&:nm_id)

        product_ids.map do |product_id|
          build_row(product_id.to_s, records.fetch(product_id, []), currency: nil) do |stats|
            aggregate_wb(stats)
          end
        end
      end

      def ozon_rows(group, period)
        platform_sku_ids = group.fetch(:products).filter_map { |product| product.platform_sku_id.to_s.presence }.uniq
        stats = RawOzon::AdSkuDailyStat.where(
          account_id: group.fetch(:account_id),
          ozon_sku_id: platform_sku_ids,
          stat_date: period.fetch(:period_from)..period.fetch(:period_to)
        ).to_a
        records = preferred_ozon_stats(stats).group_by(&:ozon_sku_id)

        platform_sku_ids.map do |platform_sku_id|
          build_row(platform_sku_id, records.fetch(platform_sku_id, []), currency: "RUB") do |selected|
            aggregate_ozon(selected)
          end
        end
      end

      def build_row(platform_sku_id, records, currency:)
        metrics = yield(records)
        missing_currency = currency.nil? && records.any? do |record|
          !record.respond_to?(:currency) || record.currency.blank?
        end
        currencies = records.filter_map { |record| record.currency.presence if record.respond_to?(:currency) }.uniq
        resolved_currency = if currency
          currency
        elsif missing_currency && currencies.any?
          "MIXED"
        elsif currencies.one?
          currencies.first
        elsif currencies.any?
          "MIXED"
        end
        dates = records.map(&:stat_date).uniq
        money_available = currency.present? || (!missing_currency && currencies.one?)
        if strict_nulls && !money_available
          metrics = metrics.merge(MONEY_METRICS.index_with { nil }, MONEY_DERIVED_METRICS.index_with { nil })
        end
        metrics.merge(
          sku_code: sku.sku_code,
          platform_sku_id:,
          currency: resolved_currency,
          data_status: records.any? ? "available" : "no_records",
          days_with_data: dates.size,
          data_through: dates.max,
          data_dates: dates
        )
      end

      def aggregate_wb(records)
        metrics = empty_metrics
        metrics[:impressions] = aggregate_sum(records, :views)
        metrics[:clicks] = aggregate_sum(records, :clicks)
        metrics[:cart_additions] = aggregate_sum(records, :add_to_cart)
        metrics[:orders] = aggregate_sum(records, :orders)
        metrics[:ordered_units] = aggregate_sum(records, :ordered_units)
        metrics[:canceled] = aggregate_sum(records, :canceled)
        metrics[:spend] = aggregate_sum(records, :spend, decimal: true)
        metrics[:attributed_revenue] = aggregate_sum(records, :revenue, decimal: true)
        positions = records.filter_map { |record| record.avg_position&.to_d }
        metrics[:avg_position] = positions.any? ? (positions.sum / positions.size).round(2) : nil
        metrics[:campaign_count] = records.map(&:campaign_id).uniq.size
        metrics.merge(calculated_metrics(metrics))
      end

      def aggregate_ozon(records)
        metrics = empty_metrics
        metrics[:impressions] = aggregate_sum(records, :impressions)
        metrics[:clicks] = aggregate_sum(records, :clicks)
        metrics[:cart_additions] = aggregate_sum(records, :cart_additions)
        metrics[:orders] = aggregate_sum(records, :orders_count)
        metrics[:ordered_units] = aggregate_sum(records, :orders_count)
        metrics[:modeled_orders] = aggregate_sum(records, :model_orders_count)
        metrics[:spend] = aggregate_sum(records, :spend, decimal: true)
        metrics[:attributed_revenue] = aggregate_sum(records, :ad_revenue, decimal: true)
        metrics[:modeled_revenue] = aggregate_sum(records, :model_revenue, decimal: true)
        metrics[:campaign_count] = records.map(&:ad_unit_id).uniq.size
        metrics.merge(calculated_metrics(metrics))
      end

      def preferred_ozon_stats(records)
        records.group_by { |record| [record.ad_unit_id, record.ozon_sku_id, record.stat_date] }.values.flat_map do |rows|
          cpc_rows, other_rows = rows.partition { |row| OZON_CPC_MODELS.include?(row.cost_model) }
          preferred_cpc = cpc_rows.find { |row| row.cost_model == "cpc_history" } || cpc_rows.first
          other_rows + Array(preferred_cpc)
        end
      end

      def empty_metrics
        COUNT_METRICS.index_with(0).merge(MONEY_METRICS.index_with { BigDecimal("0") })
      end

      # A NULL source value means the metric is unknown, not zero. Keep that
      # distinction through aggregation so derived ratios cannot look valid.
      def aggregate_sum(records, method_name, decimal: false)
        return strict_sum(records, method_name, decimal: decimal) if strict_nulls

        values = records.map { |record| record.public_send(method_name) }
        decimal ? values.sum { |value| value.to_d } : values.sum { |value| value.to_i }
      end

      def strict_sum(records, method_name, decimal: false)
        values = records.map do |record|
          record.public_send(method_name) if record.respond_to?(method_name)
        end
        return if values.empty? || values.any?(&:nil?)

        decimal ? values.sum { |value| value.to_d } : values.sum { |value| value.to_i }
      end

      def calculated_metrics(metrics)
        {
          ctr_pct: percentage(metrics[:clicks], metrics[:impressions]),
          cart_conversion_pct: percentage(metrics[:cart_additions], metrics[:clicks]),
          cr_pct: percentage(metrics[:orders], metrics[:clicks]),
          avg_cpc: ratio(metrics[:spend], metrics[:clicks]),
          cpo: ratio(metrics[:spend], metrics[:orders]),
          drr_pct: percentage(metrics[:spend], metrics[:attributed_revenue]),
          roas: ratio(metrics[:attributed_revenue], metrics[:spend])
        }
      end

      def ratio(numerator, denominator)
        return nil if numerator.nil? || denominator.nil? || denominator.to_d.zero?

        (numerator.to_d / denominator.to_d).round(2)
      end

      def percentage(numerator, denominator)
        return nil if numerator.nil? || denominator.nil? || denominator.to_d.zero?

        (numerator.to_d / denominator.to_d * 100).round(2)
      end

      def positive_integer(value)
        integer = value.to_i
        integer if integer.positive?
      end
    end
  end
end
