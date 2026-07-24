module RawWb
  module Adv
    class AnalyticsQuery
      METRICS = %i[views clicks add_to_cart orders ordered_units canceled spend revenue].freeze

      def initialize(store:, from_date:, to_date:)
        @store = store
        @from_date = from_date
        @to_date = to_date
      end

      def campaign_rows(query: nil, statuses: nil)
        scope = campaigns_scope
        scope = scope.where(status: statuses) if statuses.present?
        if query.present?
          term = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
          scope = scope.where("name ILIKE :term OR CAST(advert_id AS TEXT) ILIKE :term", term:)
        end

        metrics = aggregate_campaign_stats
        budgets = latest_budgets(scope.pluck(:id))
        product_counts = RawWb::AdvCampaignProduct.where(campaign_id: scope.select(:id), is_current: true)
          .group(:campaign_id).count

        scope.order(Arel.sql("status = 9 DESC"), source_updated_at: :desc, advert_id: :desc).map do |campaign|
          values = metrics[campaign.id] || empty_metrics
          {
            campaign:,
            budget: budgets[campaign.id],
            product_count: product_counts[campaign.id].to_i,
          }.merge(values).merge(calculated_metrics(values))
        end
      end

      def product_rows(query: nil)
        scope = product_daily_scope.all_apps
        if query.present?
          term = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
          scope = scope.where("product_name ILIKE :term OR CAST(nm_id AS TEXT) ILIKE :term", term:)
        end
        grouped = aggregate_product_scope(scope)
        decorate_products(grouped)
      end

      def product_campaign_rows(nm_id)
        campaign_products = RawWb::AdvCampaignProduct.includes(:campaign).joins(:campaign).where(
          nm_id:,
          is_current: true,
          raw_wb_adv_campaigns: { store_id: @store.id, is_current: true }
        ).to_a
        configured_campaign_ids = campaign_products.map(&:campaign_id)
        stats = aggregate_product_stats_by_campaign(nm_id)
        budgets = latest_budgets(configured_campaign_ids)

        rows = campaign_products.map do |campaign_product|
          campaign = campaign_product.campaign
          values = stats.delete(campaign.id) || empty_metrics
          {
            campaign:,
            campaign_product:,
            budget: budgets[campaign.id],
          }.merge(values).merge(calculated_metrics(values))
        end.sort_by { |row| [row[:campaign].status == 9 ? 0 : 1, -row[:spend].to_d, row[:campaign].advert_id] }

        other_values = stats.values.each_with_object(empty_metrics) do |values, total|
          METRICS.each { |metric| total[metric] += values[metric].to_d }
        end
        other_row = other_values.values.any?(&:positive?) ? other_values.merge(calculated_metrics(other_values)) : nil
        { rows:, other_row: }
      end

      def campaign_product_rows(campaign)
        products = campaign.products.where(is_current: true).order(:nm_id).to_a
        metrics = aggregate_product_scope(product_daily_scope.all_apps.where(campaign_id: campaign.id))
          .index_by { |row| row[:nm_id] }
        product_names = raw_product_names(products.map(&:nm_id))
        sku_products = sku_products_by_nm(products.map(&:nm_id))

        products.map do |product|
          values = metrics[product.nm_id] || empty_metrics.merge(nm_id: product.nm_id, avg_position: nil)
          {
            campaign_product: product,
            product_name: product_names[product.nm_id] || values[:product_name],
            sku_product: sku_products[product.nm_id],
          }.merge(values).merge(calculated_metrics(values))
        end
      end

      def summary(rows)
        values = empty_metrics
        rows.each { |row| METRICS.each { |metric| values[metric] += row[metric].to_d } }
        values.merge(calculated_metrics(values))
      end

      def campaign_summary(campaign)
        values = aggregate_campaign_stats[campaign.id] || empty_metrics
        values.merge(calculated_metrics(values))
      end

      private

      def campaigns_scope
        RawWb::AdvCampaign.where(store_id: @store.id, is_current: true)
      end

      def campaign_daily_scope
        RawWb::AdvCampaignDailyStat.joins(:campaign).where(
          raw_wb_adv_campaigns: { store_id: @store.id },
          stat_date: @from_date..@to_date
        )
      end

      def product_daily_scope
        RawWb::AdvProductDailyStat.joins(:campaign).where(
          raw_wb_adv_campaigns: { store_id: @store.id },
          stat_date: @from_date..@to_date
        )
      end

      def aggregate_campaign_stats
        aggregate_scope(campaign_daily_scope, :campaign_id)
      end

      def aggregate_scope(scope, key)
        result = Hash.new { |hash, value| hash[value] = empty_metrics }
        scope.find_each do |record|
          METRICS.each { |metric| result[record.public_send(key)][metric] += record.public_send(metric).to_d }
        end
        result
      end

      def aggregate_product_scope(scope)
        rows = scope.group(:nm_id).pluck(
          :nm_id,
          Arel.sql("MAX(product_name)"),
          Arel.sql("COUNT(DISTINCT campaign_id)"),
          Arel.sql("SUM(views)"),
          Arel.sql("SUM(clicks)"),
          Arel.sql("SUM(add_to_cart)"),
          Arel.sql("SUM(orders)"),
          Arel.sql("SUM(ordered_units)"),
          Arel.sql("SUM(canceled)"),
          Arel.sql("SUM(spend)"),
          Arel.sql("SUM(revenue)"),
          Arel.sql("AVG(avg_position)")
        )
        rows.map do |nm_id, product_name, campaign_count, views, clicks, carts, orders, units, canceled, spend, revenue, position|
          empty_metrics.merge(
            nm_id:, product_name:, campaign_count: campaign_count.to_i,
            views: views.to_d, clicks: clicks.to_d, add_to_cart: carts.to_d,
            orders: orders.to_d, ordered_units: units.to_d, canceled: canceled.to_d,
            spend: spend.to_d, revenue: revenue.to_d, avg_position: position&.to_d
          )
        end
      end

      def aggregate_product_stats_by_campaign(nm_id)
        result = Hash.new { |hash, campaign_id| hash[campaign_id] = empty_metrics }
        positions = Hash.new { |hash, campaign_id| hash[campaign_id] = [] }
        product_daily_scope.all_apps.where(nm_id:).find_each do |record|
          METRICS.each { |metric| result[record.campaign_id][metric] += record.public_send(metric).to_d }
          positions[record.campaign_id] << record.avg_position.to_d if record.avg_position.present?
        end
        positions.each { |campaign_id, values| result[campaign_id][:avg_position] = values.sum / values.size }
        result
      end

      def decorate_products(rows)
        nm_ids = rows.map { |row| row[:nm_id] }
        product_names = raw_product_names(nm_ids)
        sku_products = sku_products_by_nm(nm_ids)
        campaign_counts = configured_campaign_counts(nm_ids)
        rows.map do |row|
          row.merge(
            product_name: product_names[row[:nm_id]] || row[:product_name],
            sku_product: sku_products[row[:nm_id]],
            campaign_count: campaign_counts[row[:nm_id]].to_i
          ).merge(calculated_metrics(row))
        end.sort_by { |row| [-row[:spend].to_d, row[:nm_id]] }
      end


      def configured_campaign_counts(nm_ids)
        RawWb::AdvCampaignProduct.joins(:campaign).where(
          nm_id: nm_ids,
          is_current: true,
          raw_wb_adv_campaigns: { store_id: @store.id, is_current: true }
        ).group(:nm_id).count
      end

      def raw_product_names(nm_ids)
        return {} if nm_ids.empty? || @store.wb_raw_account_id.blank?

        RawWb::Product.where(account_id: @store.wb_raw_account_id, nm_id: nm_ids).pluck(:nm_id, :title).to_h
      end

      def sku_products_by_nm(nm_ids)
        return {} if nm_ids.empty?

        Ec::SkuProduct.includes(:sku).where(store_id: @store.id, platform: "wb", product_id: nm_ids.map(&:to_s))
          .index_by { |product| product.product_id.to_i }
      end

      def latest_budgets(campaign_ids)
        RawWb::AdvBudgetSnapshot.where(campaign_id: campaign_ids).order(observed_at: :desc)
          .each_with_object({}) { |budget, result| result[budget.campaign_id] ||= budget }
      end

      def empty_metrics
        METRICS.index_with { BigDecimal("0") }
      end

      def calculated_metrics(values)
        {
          ctr: percentage(values[:clicks], values[:views]),
          cpc: ratio(values[:spend], values[:clicks]),
          cpo: ratio(values[:spend], values[:orders]),
          cr: percentage(values[:orders], values[:clicks]),
          cpm: ratio(values[:spend] * 1000, values[:views]),
          drr: percentage(values[:spend], values[:revenue]),
          roas: ratio(values[:revenue], values[:spend]),
        }
      end

      def ratio(numerator, denominator)
        return nil if denominator.to_d.zero?

        numerator.to_d / denominator.to_d
      end

      def percentage(numerator, denominator)
        value = ratio(numerator, denominator)
        value * 100 if value
      end
    end
  end
end
