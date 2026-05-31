module RawOzon
  module Syncs
    module PostingsFbs
      # POST /v3/posting/fbs/list (offset pagination，30天分窗避免 PERIOD_IS_TOO_LONG)
      def sync_postings_fbs
        total     = 0
        synced_at = Time.current

        date_chunks(chunk_days: 30).each do |from, to|
          offset = 0
          loop do
            resp = @client.post('/v3/posting/fbs/list', {
              dir:    'asc',
              filter: { since: from.beginning_of_day.iso8601, to: to.end_of_day.iso8601, status: '' },
              limit:  50,
              offset: offset,
              with:   { analytics_data: true, financial_data: true },
            })
            postings = Array(resp.dig('result', 'postings'))
            break if postings.empty?

            posting_rows = postings.map { |p| build_posting_fbs(p, synced_at) }
            RawOzon::PostingFbs.upsert_all(posting_rows, unique_by: [:account_id, :posting_number],
                                            update_only: posting_fbs_update_cols)

            item_rows = postings.flat_map { |p| build_posting_items(p, 'fbs', synced_at) }
            if item_rows.any?
              RawOzon::PostingItem.where(account_id: @account.id,
                                         posting_number: item_rows.map { |r| r[:posting_number] }.uniq,
                                         posting_type: 'fbs').delete_all
              RawOzon::PostingItem.insert_all(item_rows)
            end

            total  += posting_rows.size
            offset += 50
            break unless resp.dig('result', 'has_next')
            sleep 0.5
          end
          sleep 1
        end

        total
      end

      private

      def build_posting_fbs(p, synced_at)
        dm = p['delivery_method'] || {}
        {
          account_id:                   @account.id,
          posting_number:               p['posting_number'],
          order_id:                     p['order_id'],
          order_number:                 p['order_number'],
          parent_posting_number:        p['parent_posting_number'].presence,
          status:                       p['status'],
          substatus:                    p['substatus'],
          delivery_method_id:           dm['id'],
          delivery_method_name:         dm['name'],
          tpl_integration_type:         p['tpl_integration_type'],
          tracking_number:              p['tracking_number'].presence,
          is_express:                   p['is_express'] || false,
          is_multibox:                  p['is_multibox'] || false,
          multi_box_qty:                p['multi_box_qty'] || 1,
          customer_id:                  p.dig('customer', 'id'),
          addressee_name:               p.dig('addressee', 'name'),
          financial_data:               p['financial_data'],
          analytics_data:               p['analytics_data'],
          requirements:                 p['requirements'],
          cancellation:                 p['cancellation'],
          raw_json:                     p,
          in_process_at:                p['in_process_at'],
          shipment_date:                p['shipment_date'],
          shipment_date_without_delay:  p['shipment_date_without_delay'],
          delivering_date:              p['delivering_date'],
          created_at:                   p['created_at'] || Time.current,
          synced_at:                    synced_at,
        }
      end

      def posting_fbs_update_cols
        %i[status substatus tracking_number financial_data analytics_data
           shipment_date delivering_date synced_at]
      end

      def build_posting_items(p, type, synced_at)
        Array(p['products']).map do |item|
          fin_product = Array(p.dig('financial_data', 'products'))
                          .find { |fp| fp['product_id'] == item['sku'] } || {}
          {
            account_id:         @account.id,
            posting_number:     p['posting_number'],
            posting_type:       type,
            ozon_sku:           item['sku'],
            offer_id:           item['offer_id'],
            name:               item['name'],
            quantity:           item['quantity'].to_i,
            price:              item['price'].to_f,
            old_price:          item['old_price'].to_f,
            currency_code:      item['currency_code'],
            payout:             fin_product['payout'].to_f,
            commission_amount:  fin_product['commission_amount'].to_f,
            commission_percent: fin_product['commission_percent'].to_f,
            raw_json:           item,
            synced_at:          synced_at,
          }
        end
      end
    end
  end
end
