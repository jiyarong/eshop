module RawWb
  module Syncs
    module SalesReports
      # POST /api/finance/v1/sales-reports/list — finance-api (settlement reports list)
      def sync_sales_reports
        body    = { dateFrom: @from.iso8601, dateTo: Date.current.iso8601 }
        data    = @client.post(:finance, '/api/finance/v1/sales-reports/list', body)
        reports = Array(data.is_a?(Hash) ? data['reports'] || data : data)
        return 0 if reports.empty?

        rows = reports.filter_map { |r| build_sales_report(r) }
        RawWb::SalesReport.upsert_all(rows, unique_by: :wb_report_id,
          update_only: %i[total_sales total_returns total_commission total_delivery
                          total_penalty net_payable synced_at]) if rows.any?
        rows.size
      end

      # POST /api/finance/v1/sales-reports/detailed/{reportId} — line items per report
      def sync_sales_report_items
        reports = RawWb::SalesReport.where(account_id: @account.id)
                                    .where('date_to >= ?', @from)
                                    .order(:date_from)
        return 0 if reports.none?

        total = 0
        reports.each do |report|
          body  = {}
          items = @client.post(:finance, "/api/finance/v1/sales-reports/detailed/#{report.wb_report_id}", body)
          items = Array(items.is_a?(Hash) ? items['items'] || items['data'] || items : items)
          next if items.empty?

          rows = items.filter_map { |item| build_sales_report_item(item, report) }
          RawWb::SalesReportItem.upsert_all(rows, unique_by: :idx_wb_sales_report_items_unique,
            update_only: %i[retail_amount commission_percent delivery_rub penalty
                            additional_payment ppvz_for_pay]) if rows.any?
          total += rows.size
          sleep 2
        end
        total
      end

      private

      def build_sales_report(r)
        report_id = r['realizationreport_id'] || r['reportId'] || r['id']
        return nil if report_id.blank?
        {
          account_id:        @account.id,
          wb_report_id:      report_id,
          date_from:         r['date_from'],
          date_to:           r['date_to'],
          report_created_at: r['create_dt'],
          total_sales:       r['total_sales'].to_f,
          total_returns:     r['total_returns'].to_f,
          total_commission:  r['total_commission'].to_f,
          total_delivery:    r['total_delivery'].to_f,
          total_penalty:     r['total_penalty'].to_f,
          net_payable:       r['net_payable'].to_f,
          synced_at:         Time.current,
        }
      end

      def build_sales_report_item(item, report)
        srid = item['srid'].presence
        doc_type = item['doc_type_name'].presence
        return nil if srid.blank? && doc_type.blank?
        {
          sales_report_id:    report.id,
          account_id:         @account.id,
          nm_id:              item['nm_id'],
          sa_name:            item['sa_name'],
          ts_name:            item['ts_name'],
          barcode:            item['barcode'],
          brand_name:         item['brand_name'],
          subject_name:       item['subject_name'],
          doc_type:           doc_type,
          quantity:           item['quantity'].to_i,
          retail_price:       item['retail_price'].to_f,
          retail_amount:      item['retail_amount'].to_f,
          sale_percent:       item['sale_percent'].to_i,
          commission_percent: item['commission_percent'].to_f,
          delivery_rub:       item['delivery_rub'].to_f,
          penalty:            item['penalty'].to_f,
          additional_payment: item['additional_payment'].to_f,
          ppvz_for_pay:       item['ppvz_for_pay'].to_f,
          srid:               srid,
          order_dt:           item['order_dt'],
          sale_dt:            item['sale_dt'],
        }
      end
    end
  end
end
