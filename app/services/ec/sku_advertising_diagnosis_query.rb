module Ec
  class SkuAdvertisingDiagnosisQuery
    MAX_DAYS = 35
    OZON_CPC_MODELS = %w[cpc cpc_history].freeze

    def initialize(sku:, from_date:, to_date:)
      @sku = sku
      @from_date = from_date.to_date
      @to_date = to_date.to_date
      raise ArgumentError, "invalid_date_range" if @from_date > @to_date
      raise ArgumentError, "date_range_too_large" if (@to_date - @from_date).to_i >= MAX_DAYS
    end

    def call
      {
        sku: @sku.sku_code,
        period: { from_date: @from_date, to_date: @to_date },
        marketing_grade: @sku.current_marketing_state&.grade,
        marketing_stage: @sku.current_marketing_state&.stage&.upcase,
        inventory_by_date: inventory_by_date,
        listings: @sku.sku_products.includes(:store).filter_map { |product| listing_payload(product) }
      }
    end

    private

    def listing_payload(product)
      case product.platform
      when "wb" then wb_payload(product)
      when "ozon" then ozon_payload(product)
      end
    end

    def wb_payload(product)
      store = product.store
      account = store.raw_wb_account
      nm_id = product.product_id.to_i
      return listing_base(product, account, nm_id).merge(data_status: "unavailable") unless account && nm_id.positive?

      campaigns = RawWb::AdvCampaign.joins(:products).where(
        store_id: store.id,
        raw_wb_adv_campaign_products: { nm_id: nm_id, is_current: true }
      ).distinct.to_a
      stats = RawWb::AdvProductDailyStat.all_apps.where(
        campaign_id: campaigns.map(&:id), nm_id: nm_id, stat_date: @from_date..@to_date
      )
      funnel_scope = RawWb::SalesFunnelDaily.where(
        account_id: account.id, nm_id: nm_id, stat_date: @from_date..@to_date
      )
      stats_by_date = stats.group_by(&:stat_date)
      funnel_by_date = funnel_scope.index_by(&:stat_date)

      listing_base(product, account, nm_id).merge(
        data_status: "available",
        data_freshness: data_freshness(stats, funnel_scope),
        campaign_summary: campaign_summary(campaigns, running: ->(campaign) { campaign.status == 9 }),
        first_ad_activity_date: first_wb_activity_date(campaigns, nm_id),
        daily: date_range.map { |date| wb_day(date, stats_by_date.fetch(date, []), funnel_by_date[date]) }
      )
    end

    def ozon_payload(product)
      store = product.store
      account = store.raw_ozon_account
      ozon_sku_id = product.platform_sku_id.to_s
      return listing_base(product, account, ozon_sku_id).merge(data_status: "unavailable") unless account && ozon_sku_id.present?

      units = RawOzon::AdUnit.joins(:products).where(
        account_id: account.id,
        raw_ozon_ad_unit_products: { ozon_sku_id: ozon_sku_id, is_current: true }
      ).distinct.to_a
      stats_scope = RawOzon::AdSkuDailyStat.where(
        account_id: account.id, ad_unit_id: units.map(&:id), ozon_sku_id: ozon_sku_id,
        stat_date: @from_date..@to_date
      )
      stats = preferred_ozon_stats(stats_scope.to_a).group_by(&:stat_date)
      funnel_scope = RawOzon::SalesFunnelDaily.where(
        account_id: account.id, sku: ozon_sku_id.to_i, stat_date: @from_date..@to_date
      )
      funnel = funnel_scope.index_by(&:stat_date)

      listing_base(product, account, ozon_sku_id).merge(
        data_status: "available",
        data_freshness: data_freshness(stats_scope, funnel_scope),
        campaign_summary: campaign_summary(units, running: ->(unit) { unit.state == "CAMPAIGN_STATE_RUNNING" }),
        first_ad_activity_date: first_ozon_activity_date(units, ozon_sku_id),
        daily: date_range.map { |date| ozon_day(date, stats.fetch(date, []), funnel[date]) }
      )
    end

    def preferred_ozon_stats(stats)
      stats.group_by { |stat| [stat.ad_unit_id, stat.ozon_sku_id, stat.stat_date] }.values.flat_map do |rows|
        cpc_rows, other_rows = rows.partition { |row| OZON_CPC_MODELS.include?(row.cost_model) }
        preferred_cpc = cpc_rows.find { |row| row.cost_model == "cpc_history" } || cpc_rows.first
        other_rows + Array(preferred_cpc)
      end
    end

    def wb_day(date, stats, funnel)
      advertising = sum_metrics(stats, views: :views, clicks: :clicks, carts: :add_to_cart,
        orders: :orders, units: :ordered_units, spend: :spend, revenue: :revenue)
      overall = funnel_metrics(funnel, views: :open_card, carts: :add_to_cart, orders: :orders, revenue: :orders_sum)
      day_payload(date, advertising, overall, stats.any?)
    end

    def ozon_day(date, stats, funnel)
      advertising = sum_metrics(stats, views: :impressions, clicks: :clicks, carts: :cart_additions,
        orders: :orders_count, units: :orders_count, spend: :spend, revenue: :ad_revenue)
      overall = funnel_metrics(funnel, views: :hits_view, carts: :hits_tocart, orders: :ordered_units, revenue: :revenue)
      day_payload(date, advertising, overall, stats.any?)
    end

    def day_payload(date, advertising, overall, ad_data_present)
      {
        date: date,
        inventory_constrained: inventory_by_date.dig(date, :out_of_stock) == true,
        ad_data_present: ad_data_present,
        advertising: advertising.merge(ad_metrics(advertising)),
        overall_funnel: overall,
        attributed_revenue_share_pct: percentage(advertising[:revenue], overall[:revenue])
      }
    end

    def sum_metrics(rows, **mapping)
      mapping.to_h do |output, source|
        [output, rows.sum { |row| row.public_send(source).to_d }.to_f]
      end
    end

    def funnel_metrics(row, **mapping)
      mapping.to_h { |output, source| [output, row&.public_send(source)&.to_d&.to_f] }
    end

    def ad_metrics(values)
      {
        ctr_pct: percentage(values[:clicks], values[:views]),
        click_to_cart_pct: percentage(values[:carts], values[:clicks]),
        click_to_order_pct: percentage(values[:orders], values[:clicks]),
        cpc: ratio(values[:spend], values[:clicks]),
        cpo: ratio(values[:spend], values[:orders]),
        drr_pct: percentage(values[:spend], values[:revenue])
      }
    end

    def listing_base(product, account, platform_sku_id)
      {
        platform: product.platform,
        store_id: product.store_id,
        store_name: product.store.store_name,
        platform_sku_id: platform_sku_id.to_s,
        currency: "RUB",
        account_id: account&.id
      }
    end

    def campaign_summary(campaigns, running:)
      { total: campaigns.size, running: campaigns.count(&running), ids: campaigns.map { |item| item.respond_to?(:advert_id) ? item.advert_id.to_s : item.external_id } }
    end

    def data_freshness(ad_scope, funnel_scope)
      {
        advertising: source_freshness(ad_scope),
        overall_funnel: source_freshness(funnel_scope)
      }
    end

    def source_freshness(scope)
      {
        latest_stat_date: scope.maximum(:stat_date),
        latest_synced_at: scope.maximum(:synced_at),
        covered_dates: scope.distinct.count(:stat_date)
      }
    end

    def first_wb_activity_date(campaigns, nm_id)
      RawWb::AdvProductDailyStat.where(campaign_id: campaigns.map(&:id), nm_id: nm_id).minimum(:stat_date)
    end

    def first_ozon_activity_date(units, ozon_sku_id)
      RawOzon::AdSkuDailyStat.where(ad_unit_id: units.map(&:id), ozon_sku_id: ozon_sku_id).minimum(:stat_date)
    end

    def inventory_by_date
      @inventory_by_date ||= Ec::Snapshot.of_type(Ec::InventorySnapshot.snapshot_type).for_sku(@sku)
        .between(@from_date, @to_date).index_by(&:snapshot_date).transform_values do |snapshot|
          { out_of_stock: snapshot.data.dig(:overview, :out_of_stock) == true }
        end
    end

    def date_range = (@from_date..@to_date).to_a

    def ratio(numerator, denominator)
      return if denominator.to_d.zero?
      (numerator.to_d / denominator.to_d).round(4).to_f
    end

    def percentage(numerator, denominator)
      value = ratio(numerator, denominator)
      (value * 100).round(2) if value
    end
  end
end
