module RawWb
  module Syncs
    module FinanceDetails
      # POST /api/finance/v1/sales-reports/detailed
      # Body: { dateFrom, dateTo, limit, rrdid }
      # 游标分页：rrdid=0 起始，取响应末行 rrdId 作为下次游标；返回行数 < limit 结束。
      def sync_finance_details
        rrdid = 0
        total = 0

        loop do
          body = {
            dateFrom: @from.iso8601,
            dateTo:   Date.current.iso8601,
            limit:    100_000,
            rrdid:    rrdid,
          }
          resp  = @client.post(:finance, '/api/finance/v1/sales-reports/detailed', body)
          items = resp.is_a?(Array) ? resp : Array(resp['data'] || resp['items'] || resp)
          break if items.empty?

          rows = items.filter_map { |r| build_finance_detail(r) }
          if rows.any?
            RawWb::FinanceDetail.upsert_all(
              rows,
              unique_by: :idx_raw_wb_finance_details_unique,
              update_only: %i[for_pay acquiring_fee delivery_rub vw penalty rebill_logistic_cost
                              ppvz_reward retail_price_with_disc retail_amount commission_percent
                              quantity country office_name ppvz_office_name delivery_method
                              bonus_type_name synced_at]
            )
          end

          total += rows.size
          rrdid  = items.last['rrdId'].to_i
          break if items.size < 100_000
          sleep 2
        end

        total
      end

      private

      def build_finance_detail(r)
        rrdid = r['rrdId'].to_i
        return nil if rrdid.zero?

        {
          account_id:             @account.id,
          rrdid:                  rrdid,
          nm_id:                  r['nmId'],
          shk_id:                 r['shkId'],
          sa_name:                r['vendorCode'],
          ts_name:                r['techSize'],
          barcode:                r['sku'],
          brand_name:             r['brandName'],
          subject_name:           r['subjectName'],
          seller_oper_name:       r['sellerOperName'] || '',
          report_type:            r['reportType'].to_i,
          retail_price:           r['retailPrice'].to_f,
          retail_price_with_disc: r['retailPriceWithDisc'].to_f,
          retail_amount:          r['retailAmount'].to_f,
          sale_percent:           r['salePercent'].to_i,
          commission_percent:     r['commissionPercent'].to_f,
          for_pay:                r['forPay'].to_f,
          acquiring_fee:          r['acquiringFee'].to_f,
          delivery_rub:           r['deliveryService'].to_f,
          vw:                     r['vw'].to_f,
          rebill_logistic_cost:   r['rebillLogisticCost'].to_f,
          ppvz_reward:            r['ppvzReward'].to_f,
          penalty:                r['penalty'].to_f,
          country:                r['country'],
          office_name:            r['officeName'],
          ppvz_office_name:       r['ppvzOfficeName'],
          delivery_method:        r['deliveryMethod'],
          paid_storage:           r['paidStorage'].to_f,
          deduction:              r['deduction'].to_f,
          bonus_type_name:        r['bonusTypeName'],
          quantity:               r['quantity'].to_i,
          doc_type:               r['docTypeName'],
          srid:                   r['srid'],
          order_dt:               parse_date(r['orderDt']),
          sale_dt:                parse_date(r['saleDt']),
          synced_at:              Time.current,
        }
      end

      def parse_date(val)
        return nil if val.blank?
        val.is_a?(String) ? val.to_date : val
      rescue ArgumentError
        nil
      end
    end
  end
end
