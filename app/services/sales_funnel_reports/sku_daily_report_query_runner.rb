module SalesFunnelReports
  class SkuDailyReportQueryRunner < ReportQueryRunner
    private

    def validate_period!(from_date, to_date)
      raise ArgumentError, "invalid_date_range" if to_date < from_date
    end

    def wb_rows(account, parsed)
      scope = account.sales_funnel_daily.where(stat_date: parsed[:from_date]..parsed[:to_date])
      mapping = platform_product_mapping("wb", account.id, :product_id)
      ids = mapped_product_ids(mapping, parsed[:sku_codes])
      scope = scope.where(nm_id: ids) if parsed[:sku_codes].any?

      grouped_platform_records(scope.order(:nm_id, :stat_date), mapping, :nm_id).map do |product, records|
        open_card = sum(records, :open_card)
        add_to_cart = sum(records, :add_to_cart)
        orders = sum(records, :orders)
        buyouts = sum(records, :buyouts)
        {
          sku_code: product&.fetch(:sku_code) || records.first.nm_id.to_s,
          product_name: product&.fetch(:product_name),
          open_card: open_card,
          add_to_cart: add_to_cart,
          conv_to_cart: percent(add_to_cart, open_card),
          cart_to_order: percent(orders, add_to_cart),
          orders: orders,
          orders_sum: sum(records, :orders_sum),
          buyouts: buyouts,
          buyouts_sum: sum(records, :buyouts_sum),
          buyout_percent: percent(buyouts, orders),
          cancel_count: sum(records, :cancel_count),
          cancel_sum: sum(records, :cancel_sum),
          add_to_wishlist: sum(records, :add_to_wishlist),
          stock_wb: latest_daily_records(records, :nm_id).sum { |record| record.stock_wb.to_i },
          stock_mp: latest_daily_records(records, :nm_id).sum { |record| record.stock_mp.to_i }
        }
      end.sort_by { |row| [-row[:orders_sum].to_d, row[:sku_code].to_s] }
    end

    def ozon_rows(account, parsed)
      scope = account.sales_funnel_daily.where(stat_date: parsed[:from_date]..parsed[:to_date])
      mapping = platform_product_mapping("ozon", account.id, :platform_sku_id)
      ids = mapped_product_ids(mapping, parsed[:sku_codes]).map(&:to_i)
      scope = scope.where(sku: ids) if parsed[:sku_codes].any?

      grouped_platform_records(scope.order(:sku, :stat_date), mapping, :sku).map do |product, records|
        hits_view = sum(records, :hits_view)
        hits_tocart = sum(records, :hits_tocart)
        hits_view_pdp = sum(records, :hits_view_pdp)
        hits_tocart_pdp = sum(records, :hits_tocart_pdp)
        {
          sku_code: product&.fetch(:sku_code) || records.first.sku.to_s,
          product_name: product&.fetch(:product_name),
          hits_view: hits_view,
          hits_view_search: sum(records, :hits_view_search),
          hits_view_pdp: hits_view_pdp,
          session_view: sum(records, :session_view),
          hits_tocart: hits_tocart,
          hits_tocart_search: sum(records, :hits_tocart_search),
          hits_tocart_pdp: hits_tocart_pdp,
          conv_tocart: percent(hits_tocart_pdp, hits_view_pdp),
          ordered_units: sum(records, :ordered_units),
          revenue: sum(records, :revenue),
          returns_count: sum(records, :returns_count),
          cancellations: sum(records, :cancellations),
          position_category: average(records, :position_category)
        }
      end.sort_by { |row| [-row[:revenue].to_d, row[:sku_code].to_s] }
    end

    def latest_daily_records(records, platform_id_field)
      records.group_by { |record| record.public_send(platform_id_field) }.values.map do |platform_records|
        platform_records.max_by(&:stat_date)
      end
    end
  end
end
