module RawWb
  module Syncs
    module ProductCards
      # POST /content/v2/get/cards/list — content-api (cursor pagination)
      # Each card has a sizes[] array: chrtID/techSize/wbSize/skus(barcodes) → product_skus
      def sync_product_cards
        cursor = nil
        total  = 0
        synced_product_ids = []

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

          record_listing_card_changes(cards)
          subject_id_by_wb_id = RawWb::Subject.where(wb_id: cards.filter_map { |c| c['subjectID'] }).pluck(:wb_id, :id).to_h
          product_rows = cards.filter_map { |c| build_product_card(c, subject_id_by_wb_id) }
          synced_product_ids.concat(product_rows.map { |row| row[:nm_id] })
          if product_rows.any?
            RawWb::Product.upsert_all(product_rows, unique_by: :nm_id,
              update_only: %i[imt_id brand title description subject_id subject_name synced_at])
          end

          # Sync SKUs for this batch
          nm_ids    = product_rows.map { |r| r[:nm_id] }
          id_map    = RawWb::Product.where(nm_id: nm_ids).pluck(:nm_id, :id).to_h
          sku_rows  = cards.flat_map { |c| build_sku_rows(c, id_map) }
          if sku_rows.any?
            RawWb::ProductSku.upsert_all(sku_rows, unique_by: :chrt_id,
              update_only: %i[tech_size wb_size barcode skus])
          end

          characteristic_rows = cards.flat_map { |c| build_characteristic_rows(c, id_map) }
          if characteristic_rows.any?
            product_ids = characteristic_rows.map { |r| r[:product_id] }.uniq
            RawWb::ProductCharacteristic.where(product_id: product_ids).delete_all
            RawWb::ProductCharacteristic.insert_all(characteristic_rows)
          end

          replace_product_media(cards, id_map)

          total += product_rows.size

          next_cursor = data['cursor']
          break if next_cursor.nil? || cards.size < 100
          cursor = { updatedAt: next_cursor['updatedAt'], nmID: next_cursor['nmID'] }
          sleep 0.7
        end

        sync_sku_product_activity(synced_product_ids)
        total
      end

      private

      def record_listing_card_changes(cards)
        products = RawWb::Product
          .includes(:product_characteristics, :product_skus, :product_media)
          .where(account_id: @account.id, nm_id: cards.filter_map { |card| card['nmID'] })
          .index_by(&:nm_id)

        cards.each do |card|
          product = products[card['nmID']]
          next unless product

          sku_product = wb_sku_product(product.nm_id)
          next unless sku_product

          Ec::ListingChangeRecorder.record(
            sku_product: sku_product,
            operation_type: "listing_content",
            before: wb_content_snapshot(product),
            after: wb_card_content_snapshot(card)
          )
          Ec::ListingChangeRecorder.record(
            sku_product: sku_product,
            operation_type: "listing_specification",
            before: wb_specification_snapshot(product),
            after: wb_card_specification_snapshot(card)
          )
        end
      end

      def wb_content_snapshot(product)
        {
          brand: product.brand,
          title: product.title,
          description: product.description,
          category: product.subject_name,
          images: product.product_media.order(:position, :id).pluck(:url)
        }
      end

      def wb_card_content_snapshot(card)
        {
          brand: card['brand'],
          title: card['title'],
          description: card['description'],
          category: card['subjectName'],
          images: media_items(card).map { |item| item.fetch(:url) }
        }
      end

      def wb_specification_snapshot(product)
        {
          characteristics: product.product_characteristics.sort_by(&:charc_id).to_h do |item|
            [item.charc_id.to_s, { name: item.charc_name, value: item.value }]
          end,
          variants: product.product_skus.sort_by(&:chrt_id).to_h do |item|
            [item.chrt_id.to_s, {
              tech_size: item.tech_size,
              wb_size: item.wb_size,
              barcodes: Array(item.skus)
            }]
          end
        }
      end

      def wb_card_specification_snapshot(card)
        {
          characteristics: Array(card['characteristics']).sort_by { |item| item['id'].to_i }.to_h do |item|
            [item['id'].to_s, { name: item['name'], value: item['value'] }]
          end,
          variants: Array(card['sizes']).sort_by { |item| item['chrtID'].to_i }.to_h do |item|
            [item['chrtID'].to_s, {
              tech_size: item['techSize'],
              wb_size: item['wbSize'],
              barcodes: Array(item['skus'])
            }]
          end
        }
      end

      def replace_product_media(cards, id_map)
        product_ids = id_map.values
        RawWb::ProductMedium.where(product_id: product_ids).delete_all if product_ids.any?

        now = Time.current
        rows = cards.flat_map do |card|
          product_id = id_map[card['nmID']]
          next [] unless product_id

          media_items(card).each_with_index.map do |item, position|
            item.merge(product_id: product_id, position: position, created_at: now, updated_at: now)
          end
        end
        RawWb::ProductMedium.insert_all(rows) if rows.any?
      end

      def media_items(card)
        photos = Array(card['photos']).filter_map do |photo|
          url = photo.is_a?(Hash) ? photo['big'] || photo['c516x688'] || photo['c246x328'] || photo['square'] : photo
          { media_type: 'image', url: url } if url.present?
        end
        video = card['video']
        photos << { media_type: 'video', url: video } if video.present?
        photos
      end

      def wb_sku_product(nm_id)
        store = wb_store
        return unless store

        Ec::SkuProduct.includes(:sku, :store).find_by(store: store, product_id: nm_id.to_s)
      end

      def wb_store
        @wb_store ||= Ec::Store.find_by(platform: 'wb', wb_raw_account_id: @account.id)
      end

      def sync_sku_product_activity(product_ids)
        store = wb_store
        return unless store

        scope = Ec::SkuProduct.where(store_id: store.id, platform: "wb")
        product_ids = product_ids.compact.map(&:to_s).uniq
        scope.where(product_id: product_ids).update_all(is_active: true, updated_at: Time.current) if product_ids.any?
        scope.where.not(product_id: product_ids).update_all(is_active: false, updated_at: Time.current)
      end

      def build_product_card(c, subject_id_by_wb_id)
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
          subject_id:   subject_id_by_wb_id[c['subjectID']],
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

      def build_characteristic_rows(c, id_map)
        nm_id      = c['nmID']
        product_id = id_map[nm_id]
        return [] unless product_id

        Array(c['characteristics']).filter_map do |characteristic|
          charc_id = characteristic['id']
          next if charc_id.blank?

          {
            product_id: product_id,
            charc_id:   charc_id,
            charc_name: characteristic['name'],
            value:      characteristic['value'],
          }
        end
      end
    end
  end
end
