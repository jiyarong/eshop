module SalesFunnelReports
  class SkuDailyTrendQuery
    WB_METRICS = %i[
      open_card add_to_cart orders buyouts orders_sum buyouts_sum conv_to_cart cart_to_order
      buyout_percent cancel_count add_to_wishlist
    ].freeze
    OZON_METRICS = %i[
      position_category hits_view hits_view_pdp hits_tocart_pdp search_to_card_conversion conv_tocart cart_to_order
      order_conversion average_price ordered_units revenue total_drr cancellations
      returns_count delivered_units total_ending_inventory store_ending_inventory
    ].freeze
    DEFAULT_METRICS = {
      "wb" => %i[open_card add_to_cart orders buyouts],
      "ozon" => %i[position_category hits_view conv_tocart ordered_units revenue]
    }.freeze

    def initialize(sku:, from_date:, to_date:)
      @sku = sku
      @from_date = from_date.to_date
      @to_date = to_date.to_date
    end

    def call
      sku.sku_products.includes(:store)
        .select { |product| product.platform.in?(%w[wb ozon]) }
        .group_by(&:store_id)
        .values
        .filter_map { |products| build_store_trend(products) }
        .sort_by do |trend|
          [-trend[:data_days], -trend[:data_volume], trend[:platform], trend[:store_name]]
        end
    end

    private

    attr_reader :sku, :from_date, :to_date

    def build_store_trend(products)
      store = products.first.store
      return unless store&.is_active?

      platform = store.platform
      records = platform == "wb" ? wb_records(store, products) : ozon_records(store, products)
      return unless records

      metrics = platform == "wb" ? WB_METRICS : OZON_METRICS
      rows = fill_dates(records, metrics, store:, products:)
      {
        store_id: store.id,
        store_name: store.store_name,
        platform: platform,
        metrics: metrics,
        default_metrics: DEFAULT_METRICS.fetch(platform),
        rows: rows,
        data_days: rows.count { |row| row[:values].values.any?(&:present?) },
        data_volume: rows.sum { |row| DEFAULT_METRICS.fetch(platform).sum { |metric| row.dig(:values, metric).to_f.abs } }
      }
    end

    def wb_records(store, products)
      return if store.wb_raw_account_id.blank?

      RawWb::SalesFunnelDaily
        .where(account_id: store.wb_raw_account_id, nm_id: products.map(&:product_id), stat_date: from_date..to_date)
        .order(:stat_date)
    end

    def ozon_records(store, products)
      platform_sku_ids = products.filter_map(&:platform_sku_id)
      return if store.ozon_raw_account_id.blank? || platform_sku_ids.empty?

      RawOzon::SalesFunnelDaily
        .where(account_id: store.ozon_raw_account_id, sku: platform_sku_ids, stat_date: from_date..to_date)
        .order(:stat_date)
    end

    def fill_dates(records, metrics, store:, products:)
      records_by_date = records.group_by(&:stat_date)
      ad_spend_by_sku_and_date = if store.platform == "ozon"
        OzonTotalDrrQuery.spend_by_sku_and_date(
          account_id: store.ozon_raw_account_id, from_date:, to_date:
        )
      else
        {}
      end
      inventory_by_date = store.platform == "ozon" ? ozon_inventory_by_date(store) : {}
      platform_sku_ids = products.filter_map(&:platform_sku_id).map(&:to_s)
      (from_date..to_date).map do |date|
        daily_records = records_by_date.fetch(date, [])
        values = metrics.index_with do |metric|
          aggregate_metric(
            daily_records, metric, date:, store:, platform_sku_ids:,
            ad_spend_by_sku_and_date:, inventory_by_date:
          )
        end
        { date: date.iso8601, values: values }
      end
    end

    def aggregate_metric(records, metric, date:, store:, platform_sku_ids:, ad_spend_by_sku_and_date:, inventory_by_date:)
      inventory = inventory_by_date[date]
      return inventory&.fetch(metric) if metric.in?(%i[total_ending_inventory store_ending_inventory])
      return if records.empty?

      case metric
      when :conv_to_cart then percent(records.sum(&:add_to_cart), records.sum(&:open_card))
      when :cart_to_order
        if store.platform == "ozon"
          percent(records.sum(&:ordered_units), records.sum(&:hits_tocart_pdp))
        else
          percent(records.sum(&:orders), records.sum(&:add_to_cart))
        end
      when :buyout_percent then percent(records.sum(&:buyouts), records.sum(&:orders))
      when :search_to_card_conversion then percent(records.sum(&:hits_view_pdp), records.sum(&:hits_view_search))
      when :conv_tocart then percent(records.sum(&:hits_tocart_pdp), records.sum(&:hits_view_pdp))
      when :order_conversion then percent(records.sum(&:ordered_units), records.sum(&:hits_view))
      when :average_price
        units = records.sum(&:ordered_units)
        units.positive? ? (records.sum { |record| record.revenue.to_d } / units).round(2).to_f : nil
      when :total_drr
        spend_keys = platform_sku_ids.map { |sku_id| [sku_id, date] }
        return unless spend_keys.any? { |key| ad_spend_by_sku_and_date.key?(key) }

        percent(spend_keys.sum { |key| ad_spend_by_sku_and_date.fetch(key, 0) }, records.sum { |record| record.revenue.to_d })
      when :position_category
        values = records.filter_map(&:position_category)
        values.present? ? (values.sum / values.size).to_f : nil
      else records.sum { |record| record.public_send(metric).to_d }.to_f
      end
    end

    def ozon_inventory_by_date(store)
      Ec::Snapshot.of_type(Ec::InventorySnapshot.snapshot_type)
        .where(sku_id: sku.id, snapshot_date: from_date..to_date)
        .each_with_object({}) do |snapshot, result|
          levels = Array(snapshot.data.dig(:distribution, :levels)).select do |level|
            level = level.with_indifferent_access
            level[:store_id].to_i == store.id && level[:fulfillment_type].to_s.in?(EndingInventoryQuery::STORE_STOCK_TYPES)
          end
          result[snapshot.snapshot_date] = {
            total_ending_inventory: snapshot.data.dig(:overview, :book_stock)&.to_i,
            store_ending_inventory: levels.sum { |level| level.with_indifferent_access[:quantity].to_i }
          }
        end
    end

    def percent(numerator, denominator)
      return 0.0 unless denominator.to_d.positive?

      (numerator.to_d / denominator.to_d * 100).round(2).to_f
    end
  end
end
