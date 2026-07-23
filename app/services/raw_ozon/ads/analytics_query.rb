module RawOzon
  module Ads
    class AnalyticsQuery
      METRICS = %i[impressions clicks cart_additions orders_count model_orders_count ad_revenue model_revenue spend].freeze

      def initialize(account:, from_date:, to_date:, store: nil)
        @account = account
        @from_date = from_date
        @to_date = to_date
        @store = store
      end

      def overview_rows
        units = units_scope.index_by(&:id)
        grouped = Hash.new { |hash, key| hash[key] = empty_metrics }
        daily_scope.where.not(cost_model: "cpo_all_report").find_each do |stat|
          unit = units[stat.ad_unit_id]
          next unless unit
          key = [unit.unit_type, Array(unit.placement).sort.join(",")]
          add_metrics(grouped[key], stat, metrics: daily_overview_metrics(unit))
        end
        merge_cpo_selected_report!(grouped, units)
        merge_cpo_all_report!(grouped, units)
        grouped.map do |(unit_type, placement), metrics|
          metrics.merge(unit_type: unit_type, placement: placement).merge(calculated_metrics(metrics))
        end.sort_by { |row| -row[:spend] }
      end

      def cpc_rows(query: nil, states: nil)
        scope = units_scope.where(unit_type: "cpc_campaign")
        scope = scope.where(state: states) unless states.nil?
        if query.present?
          term = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
          scope = scope.where(
            "raw_ozon_ad_units.title ILIKE :term OR raw_ozon_ad_units.external_id ILIKE :term OR EXISTS (" \
            "SELECT 1 FROM raw_ozon_ad_unit_products products " \
            "WHERE products.ad_unit_id = raw_ozon_ad_units.id " \
            "AND (products.ozon_sku_id ILIKE :term OR products.title ILIKE :term))",
            term: term
          )
        end
        metrics_by_unit = aggregate_daily_by(:ad_unit_id)
        scope.order(Arel.sql("raw_ozon_ad_units.state = 'CAMPAIGN_STATE_RUNNING' DESC"))
          .order(Arel.sql("raw_ozon_ad_units.updated_at DESC")).map do |unit|
          metrics = metrics_by_unit[unit.id] || empty_metrics
          { unit: unit, product_count: unit.products.where(is_current: true).count }
            .merge(metrics).merge(calculated_metrics(metrics))
        end
      end

      def cpc_detail(unit, query: nil, cost_models: nil)
        product_scope = unit.products.where(is_current: true)
        if query.present?
          term = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
          product_scope = product_scope.where("ozon_sku_id ILIKE :term OR title ILIKE :term", term: term)
        end
        metrics_by_sku = aggregate_sku_by(:ozon_sku_id, unit_id: unit.id, cost_models: cost_models)
        raw_products = RawOzon::Product.where(id: product_scope.where.not(raw_ozon_product_id: nil).select(:raw_ozon_product_id)).index_by(&:id)
        sku_products = internal_sku_products(product_scope.pluck(:ozon_sku_id))
        single_product_metrics = if unit.unit_type == "cpc_campaign" && unit.products.where(is_current: true).count == 1
          aggregate_scope(daily_scope.where(ad_unit_id: unit.id, cost_model: "cpc"), :ad_unit_id)[unit.id]
        end

        product_scope.order(:ozon_sku_id).map do |product|
          metrics = single_product_metrics || metrics_by_sku[product.ozon_sku_id] || empty_metrics
          sku_product = sku_products[product.ozon_sku_id.to_s]
          { product: product, raw_product: raw_products[product.raw_ozon_product_id],
            sku_product: sku_product, sku: sku_product&.sku }
            .merge(metrics).merge(calculated_metrics(metrics))
        end
      end

      def cpo_selected_rows(query: nil)
        unit = units_scope.find_by(unit_type: "cpo_selected")
        return [nil, []] unless unit
        rows = cpc_detail(unit, query: query, cost_models: ["cpo"])
        [unit, rows]
      end

      def summary(rows)
        metrics = empty_metrics
        rows.each { |row| METRICS.each { |metric| metrics[metric] += row[metric].to_d } }
        metrics.merge(calculated_metrics(metrics))
      end

      private

      def units_scope = RawOzon::AdUnit.where(account_id: @account.id)
      def daily_scope = RawOzon::AdDailyStat.where(account_id: @account.id, stat_date: @from_date..@to_date)
      def sku_daily_scope = RawOzon::AdSkuDailyStat.where(account_id: @account.id, stat_date: @from_date..@to_date)

      def internal_sku_products(ozon_sku_ids)
        return {} unless @store

        Ec::SkuProduct.includes(:sku).where(store_id: @store.id, platform: "ozon",
          platform_sku_id: ozon_sku_ids.map(&:to_s)).index_by { |product| product.platform_sku_id.to_s }
      end

      def aggregate_daily_by(column)
        aggregate_scope(daily_scope.where.not(cost_model: "cpo_all_report"), column)
      end

      def aggregate_sku_by(column, unit_id:, cost_models: nil)
        scope = sku_daily_scope.where(ad_unit_id: unit_id)
        return aggregate_scope(scope.where(cost_model: cost_models), column) if cost_models

        result = Hash.new { |hash, key| hash[key] = empty_metrics }
        scope.to_a.group_by { |record| [record.ozon_sku_id, record.stat_date] }.each_value do |records|
          record = records.find { |candidate| candidate.cost_model == "cpc_history" } || records.first
          add_metrics(result[record.public_send(column)], record)
        end
        result
      end

      def aggregate_scope(scope, column)
        result = Hash.new { |hash, key| hash[key] = empty_metrics }
        scope.find_each { |record| add_metrics(result[record.public_send(column)], record) }
        result
      end

      def empty_metrics
        METRICS.index_with { BigDecimal("0") }
      end

      def add_metrics(target, record, metrics: METRICS)
        metrics.each { |metric| target[metric] += record.public_send(metric).to_d }
      end

      def daily_overview_metrics(unit)
        case unit.unit_type
        when "cpo_selected"
          %i[spend]
        when "cpo_all"
          %i[impressions clicks cart_additions spend]
        else
          METRICS
        end
      end

      def merge_cpo_selected_report!(grouped, units)
        unit = units.values.find { |candidate| candidate.unit_type == "cpo_selected" }
        return unless unit

        key = [unit.unit_type, Array(unit.placement).sort.join(",")]
        sku_daily_scope.where(ad_unit_id: unit.id, cost_model: "cpo").find_each do |stat|
          add_metrics(grouped[key], stat, metrics: %i[orders_count model_orders_count ad_revenue model_revenue])
        end
      end

      def merge_cpo_all_report!(grouped, units)
        unit = units.values.find { |candidate| candidate.unit_type == "cpo_all" }
        return unless unit

        key = [unit.unit_type, Array(unit.placement).sort.join(",")]
        daily_scope.where(ad_unit_id: unit.id, cost_model: "cpo_all_report").find_each do |stat|
          add_metrics(grouped[key], stat, metrics: %i[orders_count model_orders_count ad_revenue model_revenue])
        end
      end

      def calculated_metrics(metrics)
        {
          ctr: ratio(metrics[:clicks], metrics[:impressions], multiplier: 100),
          avg_cpc: ratio(metrics[:spend], metrics[:clicks]),
          drr: ratio(metrics[:spend], metrics[:ad_revenue], multiplier: 100),
          cart_conversion: ratio(metrics[:cart_additions], metrics[:clicks], multiplier: 100),
          cost_per_order: ratio(metrics[:spend], metrics[:orders_count])
        }
      end

      def ratio(numerator, denominator, multiplier: 1)
        return nil if denominator.to_d.zero?
        numerator.to_d / denominator.to_d * multiplier
      end
    end
  end
end
