module ErpAI
  module V2
    class AdvertisingContext
      COUNT_METRICS = %i[impressions clicks cart_additions orders ordered_units canceled modeled_orders].freeze
      MONEY_METRICS = %i[spend attributed_revenue modeled_revenue].freeze
      OZON_CPC_MODELS = %w[cpc cpc_history].freeze

      def initialize(sku:, period_from:, period_to:, today: Date.current)
        @sku = sku
        @period_from = period_from
        @period_to = period_to
        @today = today.to_date
      end

      def call
        weekly_periods.map do |period|
          period.merge(
            is_partial: period.fetch(:period_to) > today,
            stores: store_groups.map { |group| store_payload(group, period) }
          ).merge(
            period_from: period.fetch(:period_from).iso8601,
            period_to: period.fetch(:period_to).iso8601
          )
        end
      end

      private

      attr_reader :sku, :period_from, :period_to, :today

      def weekly_periods
        (period_from..period_to).step(7).map do |week_start|
          { period_from: week_start, period_to: week_start.end_of_week(:monday) }
        end
      end

      def store_groups
        @store_groups ||= sku.sku_products.includes(:store).group_by { |product| [product.platform, product.store] }
          .filter_map do |(platform, store), products|
            account_id = platform == "wb" ? store.wb_raw_account_id : store.ozon_raw_account_id
            next if account_id.blank?

            { platform:, store:, account_id:, products: }
          end
          .sort_by { |group| [group.fetch(:platform), group.fetch(:store).id] }
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
        currencies = records.filter_map { |record| record.respond_to?(:currency) ? record.currency.presence : nil }.uniq
        resolved_currency = if currency
          currency
        elsif currencies.one?
          currencies.first
        elsif currencies.any?
          "MIXED"
        end
        dates = records.map(&:stat_date).uniq
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
        records.each do |record|
          metrics[:impressions] += record.views.to_i
          metrics[:clicks] += record.clicks.to_i
          metrics[:cart_additions] += record.add_to_cart.to_i
          metrics[:orders] += record.orders.to_i
          metrics[:ordered_units] += record.ordered_units.to_i
          metrics[:canceled] += record.canceled.to_i
          metrics[:spend] += record.spend.to_d
          metrics[:attributed_revenue] += record.revenue.to_d
        end
        positions = records.filter_map { |record| record.avg_position&.to_d }
        metrics[:avg_position] = positions.any? ? (positions.sum / positions.size).round(2) : nil
        metrics[:campaign_count] = records.map(&:campaign_id).uniq.size
        metrics.merge(calculated_metrics(metrics))
      end

      def aggregate_ozon(records)
        metrics = empty_metrics
        records.each do |record|
          metrics[:impressions] += record.impressions.to_i
          metrics[:clicks] += record.clicks.to_i
          metrics[:cart_additions] += record.cart_additions.to_i
          metrics[:orders] += record.orders_count.to_i
          metrics[:ordered_units] += record.orders_count.to_i
          metrics[:modeled_orders] += record.model_orders_count.to_i
          metrics[:spend] += record.spend.to_d
          metrics[:attributed_revenue] += record.ad_revenue.to_d
          metrics[:modeled_revenue] += record.model_revenue.to_d
        end
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
        return nil if denominator.to_d.zero?

        (numerator.to_d / denominator.to_d).round(2)
      end

      def percentage(numerator, denominator)
        return nil if denominator.to_d.zero?

        (numerator.to_d / denominator.to_d * 100).round(2)
      end

      def positive_integer(value)
        integer = value.to_i
        integer if integer.positive?
      end
    end
  end
end
