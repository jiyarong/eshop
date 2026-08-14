module SalesFunnelReports
  class SkuDailyTrendQuery
    WB_METRICS = %i[
      open_card add_to_cart orders buyouts orders_sum buyouts_sum conv_to_cart cart_to_order
      buyout_percent cancel_count add_to_wishlist
    ].freeze
    OZON_METRICS = %i[
      hits_view position_category session_view hits_tocart ordered_units revenue conv_tocart returns_count cancellations
      hits_view_search hits_view_pdp hits_tocart_search hits_tocart_pdp
    ].freeze
    DEFAULT_METRICS = {
      "wb" => %i[open_card add_to_cart orders buyouts],
      "ozon" => %i[hits_view position_category hits_tocart ordered_units revenue]
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
      rows = fill_dates(records, metrics)
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

    def fill_dates(records, metrics)
      records_by_date = records.group_by(&:stat_date)
      (from_date..to_date).map do |date|
        daily_records = records_by_date.fetch(date, [])
        values = metrics.index_with { |metric| aggregate_metric(daily_records, metric) }
        { date: date.iso8601, values: values }
      end
    end

    def aggregate_metric(records, metric)
      return if records.empty?

      case metric
      when :conv_to_cart then percent(records.sum(&:add_to_cart), records.sum(&:open_card))
      when :cart_to_order then percent(records.sum(&:orders), records.sum(&:add_to_cart))
      when :buyout_percent then percent(records.sum(&:buyouts), records.sum(&:orders))
      when :conv_tocart then percent(records.sum(&:hits_tocart), records.sum(&:hits_view))
      when :position_category
        values = records.filter_map(&:position_category)
        values.present? ? (values.sum / values.size).to_f : nil
      else records.sum { |record| record.public_send(metric).to_d }.to_f
      end
    end

    def percent(numerator, denominator)
      return 0.0 unless denominator.to_d.positive?

      (numerator.to_d / denominator.to_d * 100).round(2).to_f
    end
  end
end
