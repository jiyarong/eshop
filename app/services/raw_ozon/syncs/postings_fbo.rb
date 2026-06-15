module RawOzon
  module Syncs
    module PostingsFbo
      # POST /v2/posting/fbo/list (offset pagination)
      def sync_postings_fbo
        offset    = 0
        result    = empty_sync_count
        synced_at = Time.current
        limit     = 50

        loop do
          resp = @client.post('/v2/posting/fbo/list', {
            dir:    'asc',
            filter: { since: @from.iso8601, to: Time.current.iso8601, status: '' },
            limit:  limit,
            offset: offset,
            with:   { analytics_data: true, financial_data: true },
          })
          postings = Array(resp['result'])
          break if postings.empty?

          posting_rows = postings.map { |p| build_posting_fbo(p, synced_at) }
          merge_sync_count!(
            result,
            upsert_count_result(posting_rows, model: RawOzon::PostingFbo, unique_key: :posting_number)
          )
          RawOzon::PostingFbo.upsert_all(posting_rows, unique_by: [:account_id, :posting_number],
                                          update_only: posting_fbo_update_cols)

          item_rows = postings.flat_map { |p| build_posting_fbo_items(p, synced_at) }
          if item_rows.any?
            RawOzon::PostingItem.where(account_id: @account.id,
                                       posting_number: item_rows.map { |r| r[:posting_number] }.uniq,
                                       posting_type: 'fbo').delete_all
            RawOzon::PostingItem.insert_all(item_rows)
          end

          offset += limit
          break if postings.size < limit
          sleep 0.5
        end

        result
      end

      private

      def build_posting_fbo(p, synced_at)
        {
          account_id:        @account.id,
          posting_number:    p['posting_number'],
          order_id:          p['order_id'],
          order_number:      p['order_number'],
          status:            p['status'],
          substatus:         p['substatus'],
          cancel_reason_id:  p['cancel_reason_id'],
          financial_data:    p['financial_data'],
          analytics_data:    p['analytics_data'],
          additional_data:   p['additional_data'],
          raw_json:          p,
          in_process_at:     p['in_process_at'],
          fact_delivery_date: p['fact_delivery_date'],
          created_at:        p['created_at'] || Time.current,
          synced_at:         synced_at,
        }
      end

      def posting_fbo_update_cols
        %i[status substatus financial_data analytics_data fact_delivery_date synced_at]
      end

      def build_posting_fbo_items(p, synced_at)
        Array(p['products']).map do |item|
          fin_product = Array(p.dig('financial_data', 'products'))
                          .find { |fp| fp['product_id'] == item['sku'] } || {}
          {
            account_id:         @account.id,
            posting_number:     p['posting_number'],
            posting_type:       'fbo',
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
