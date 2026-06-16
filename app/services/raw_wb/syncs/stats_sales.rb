module RawWb
  module Syncs
    module StatsSales
      # GET /api/v1/supplier/sales — statistics-api
      # saleID prefix: S = normal sale, R = return (refund after delivery)
      # S and R share the same srid — unique key must be sale_id, not srid
      def sync_stats_sales
        data = @client.get(:statistics, '/api/v1/supplier/sales', dateFrom: @from.iso8601)
        rows = Array(data).filter_map { |r| build_stats_sale(r) }
        return 0 if rows.empty?

        rows.each do |r|
          unless r[:srid].present?
            r[:srid] = "nosrid:#{r[:account_id]}:#{r[:g_number]}:#{r[:barcode]}:#{r[:sale_date].to_s[0..9]}"
          end
          r[:sale_id] ||= r[:srid]
        end

        rows = rows.uniq { |r| r[:sale_id] }
        RawWb::StatsSale.upsert_all(rows, unique_by: %i[account_id sale_id],
          update_only: stats_sale_update_cols)
        rows.size
      end

      private

      def build_stats_sale(r)
        return nil if r['date'].blank?
        {
          account_id:       @account.id,
          sale_id:          r['saleID'].presence,
          g_number:         r['gNumber'],
          sale_date:        r['date'],
          last_change_date: r['lastChangeDate'],
          supplier_article: r['supplierArticle'],
          tech_size:        r['techSize'],
          barcode:          r['barcode'],
          total_price:      r['totalPrice'],
          discount_percent: r['discountPercent'],
          for_pay:          r['forPay'],
          finished_price:   r['finishedPrice'],
          price_with_disc:  r['priceWithDisc'],
          nm_id:            r['nmId'],
          subject:          r['subject'],
          category:         r['category'],
          brand:            r['brand'],
          is_storno:        r['isStorno'],
          srid:             r['srid'].presence,
          synced_at:        Time.current,
        }
      end

      def stats_sale_update_cols
        %i[last_change_date for_pay finished_price price_with_disc synced_at]
      end
    end
  end
end
