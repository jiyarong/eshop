module RawWb
  module Syncs
    module ProductCards
      # POST /content/v2/get/cards/list — content-api (cursor pagination)
      # Each card has a sizes[] array: chrtID/techSize/wbSize/skus(barcodes) → product_skus
      def sync_product_cards
        cursor = nil
        total  = 0

        loop do
          body = {
            settings: {
              cursor: { limit: 100 }.merge(cursor || {}),
              filter: { withPhoto: -1 },
              sort:   { ascending: false },
            },
          }
          data  = @client.post(:content, '/content/v2/get/cards/list', body)
          cards = Array(data['cards'])
          break if cards.empty?

          product_rows = cards.filter_map { |c| build_product_card(c) }
          if product_rows.any?
            RawWb::Product.upsert_all(product_rows, unique_by: :nm_id,
              update_only: %i[imt_id brand title description subject_name synced_at])
          end

          # Sync SKUs for this batch
          nm_ids    = product_rows.map { |r| r[:nm_id] }
          id_map    = RawWb::Product.where(nm_id: nm_ids).pluck(:nm_id, :id).to_h
          sku_rows  = cards.flat_map { |c| build_sku_rows(c, id_map) }
          if sku_rows.any?
            RawWb::ProductSku.upsert_all(sku_rows, unique_by: :chrt_id,
              update_only: %i[tech_size wb_size barcode skus])
          end

          total += product_rows.size

          next_cursor = data['cursor']
          break if next_cursor.nil? || cards.size < 100
          cursor = { updatedAt: next_cursor['updatedAt'], nmID: next_cursor['nmID'] }
          sleep 0.7
        end

        total
      end

      private

      def build_product_card(c)
        nm_id = c['nmID']
        return nil if nm_id.blank?
        {
          account_id:   @account.id,
          nm_id:        nm_id,
          imt_id:       c['imtID'],
          vendor_code:  c['vendorCode'].to_s,
          brand:        c['brand'],
          title:        c['title'],
          description:  c['description'],
          subject_name: c['subjectName'],
          synced_at:    Time.current,
        }
      end

      def build_sku_rows(c, id_map)
        nm_id      = c['nmID']
        product_id = id_map[nm_id]
        return [] unless product_id

        Array(c['sizes']).filter_map do |s|
          chrt_id = s['chrtID']
          next if chrt_id.blank?
          {
            product_id: product_id,
            chrt_id:    chrt_id,
            tech_size:  s['techSize'],
            wb_size:    s['wbSize'],
            barcode:    Array(s['skus']).first,
            skus:       Array(s['skus']),
          }
        end
      end
    end
  end
end
