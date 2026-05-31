module RawWb
  module Syncs
    module SalesFunnel
      # POST /api/analytics/v3/sales-funnel/products — seller-analytics-api
      def sync_sales_funnel
        end_date   = Date.current
        start_date = @from

        body = {
          filter: {
            startDate: start_date.iso8601,
            endDate:   end_date.iso8601,
          },
          selectedPeriod: {
            start: start_date.iso8601,
            end:   end_date.iso8601,
          },
          page: 1,
        }

        log body

        data     = @client.post(:seller_analytics, '/api/analytics/v3/sales-funnel/products', body)
        log data
        products = Array(data.dig('data', 'products') || data['products'] || [])

        rows = products.filter_map { |r| build_sales_funnel_row(r) }
        return 0 if rows.empty?

        RawWb::AnalyticsSalesFunnel.upsert_all(rows,
          unique_by: %i[account_id stat_date nm_id],
          update_only: %i[open_card add_to_cart orders orders_sum buyouts buyouts_sum
                          cancel_count cancel_sum conv_to_cart cart_to_order buyout_percent
                          avg_price avg_orders_per_day share_order_percent add_to_wishlist
                          localization_percent time_to_ready_days time_to_ready_hours time_to_ready_mins])
        rows.size
      end

      private

      def build_sales_funnel_row(r)
        product = r['product'] || {}
        stat    = r.dig('statistic', 'selected') || {}
        conv    = stat['conversions'] || {}
        ttr     = stat['timeToReady'] || {}

        nm_id = product['nmId']
        return nil if nm_id.blank?

        {
          account_id:           @account.id,
          stat_date:            @from,
          nm_id:                nm_id,
          vendor_code:          product['vendorCode'],
          brand:                product['brandName'],
          subject:              product['subjectName'],
          open_card:            stat['openCount'].to_i,
          add_to_cart:          stat['cartCount'].to_i,
          orders:               stat['orderCount'].to_i,
          orders_sum:           stat['orderSum'].to_f,
          buyouts:              stat['buyoutCount'].to_i,
          buyouts_sum:          stat['buyoutSum'].to_f,
          cancel_count:         stat['cancelCount'].to_i,
          cancel_sum:           stat['cancelSum'].to_f,
          conv_to_cart:         conv['addToCartPercent'].to_f,
          cart_to_order:        conv['cartToOrderPercent'].to_f,
          buyout_percent:       conv['buyoutPercent'].to_f,
          avg_price:            stat['avgPrice'].to_f,
          avg_orders_per_day:   stat['avgOrdersCountPerDay'].to_f,
          share_order_percent:  stat['shareOrderPercent'].to_f,
          add_to_wishlist:      stat['addToWishlist'].to_i,
          localization_percent: stat['localizationPercent'].to_f,
          time_to_ready_days:   ttr['days'].to_i,
          time_to_ready_hours:  ttr['hours'].to_i,
          time_to_ready_mins:   ttr['mins'].to_i,
        }
      end
    end
  end
end
