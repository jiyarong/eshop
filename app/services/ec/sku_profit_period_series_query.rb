module Ec
  class SkuProfitPeriodSeriesQuery
    include WeeklySummarySupport

    def self.run(sku:, periods:)
      new(sku:, periods:).call
    end

    def initialize(sku:, periods:)
      @sku = sku
      @sku_codes = [sku.sku_code]
      @periods = periods.map { |period| normalize_period(period) }
    end

    def call
      store_metadata = build_store_metadata

      @periods.map do |period|
        rate = Ec::WeeklyRate.resolve(period.fetch(:from_date))
        raise ArgumentError, "missing_weekly_rate" unless rate

        rows, = collect_rows(period.fetch(:from_date), period.fetch(:to_date), rate)
        sku_rows = rows.select { |row| row[:sku].to_s.casecmp?(@sku.sku_code) }
        aggregated_rows = aggregate_rows_by_sku(sku_rows)

        {
          key: period.fetch(:key),
          from_date: period.fetch(:from_date),
          to_date: period.fetch(:to_date),
          sku_row: decorate_sku_row(build_wsu_deep_row_hashes(
            aggregated_rows,
            from_date: period.fetch(:from_date),
            to_date: period.fetch(:to_date)
          ).first || {}),
          store_rows: build_wsu_row_hashes(
            sku_rows,
            from_date: period.fetch(:from_date),
            to_date: period.fetch(:to_date)
          ).map do |row|
            metadata = store_metadata[[row[:platform].to_s.downcase, row[:shop].to_s.strip]] || {}
            decorate_store_row(row, metadata)
          end
        }
      end
    end

    private

    def normalize_period(period)
      from_date = period.fetch(:from_date).to_date
      to_date = period.fetch(:to_date).to_date
      raise ArgumentError, "invalid_period" if to_date < from_date

      { key: period.fetch(:key).to_s, from_date:, to_date: }
    end

    def build_store_metadata
      products_by_store_id = @sku.sku_products.includes(:store).index_by(&:store_id)
      metadata = {}

      RawWb::SellerAccount.all.each do |account|
        store = Ec::Store.find_by(platform: "wb", wb_raw_account_id: account.id)
        metadata[["wb", account.name.to_s.strip]] = store_metadata(store, products_by_store_id[store&.id], "wb:#{account.id}")
      end
      RawOzon::SellerAccount.all.each do |account|
        store = Ec::Store.find_by(platform: "ozon", ozon_raw_account_id: account.id)
        metadata[["ozon", account.company_name.to_s.strip]] = store_metadata(store, products_by_store_id[store&.id], "ozon:#{account.id}")
      end

      metadata
    end

    def store_metadata(store, product, store_ref)
      {
        store_ref:,
        store_id: store&.id,
        store_name: store&.store_name,
        sku_product_id: product&.id,
        listing_label: product&.product_name.presence || product&.offer_id.presence || product&.product_id
      }
    end

    def decorate_store_row(row, metadata)
      row.merge(
        metadata,
        currency: "CNY",
        listing_label: metadata[:listing_label].presence || @sku.sku_code,
        cost_return_pct: percentage(row[:after_tax], row[:goods_cost]),
        other_attributable_fees: nil
      )
    end

    def decorate_sku_row(row)
      row.merge(
        currency: "CNY",
        other_attributable_fees: nil
      )
    end
  end
end
