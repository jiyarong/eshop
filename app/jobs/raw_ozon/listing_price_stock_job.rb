module RawOzon
  class ListingPriceStockJob < ApplicationJob
    queue_as :default

    def perform(publication_id)
      publication = Ec::OzonListingPublication.find(publication_id)
      return publication unless publication.ready_for_price_stock? || publication.ready_for_stock? || publication.imported? || publication.completed?

      client = RawOzon::ListingClient.for_account(publication.account)
      responses = publication.response_json.to_h.deep_dup
      payload = publication.payload.to_h.deep_symbolize_keys
      product_id = publication.product_id
      raise ArgumentError, "publication has no product_id" if product_id.blank?

      if Array(payload[:images]).present?
        image_response = client.import_pictures(
          product_id: product_id,
          images: Array(payload[:images]),
          primary_image: payload[:primary_image],
          color_image: payload[:color_image]
        )
        responses["pictures"] = image_response
        if client.respond_to?(:picture_info)
          responses["pictures_status"] = client.picture_info(product_id: product_id)
        end
      end

      price = payload[:price].to_h
      if price[:price].present?
        responses["price"] = client.import_prices([
          {
            offer_id: publication.offer_id,
            product_id: product_id,
            price: price[:price],
            old_price: price[:old_price],
            min_price: price[:min_price],
            currency_code: price[:currency_code] || payload[:currency_code]
          }.compact
        ])
      end

      stock = payload[:stock].to_h
      if stock.present?
        responses["stock"] = client.update_stocks([
          stock.merge(product_id: product_id, offer_id: publication.offer_id).stringify_keys
        ])
      end

      if client.respond_to?(:product_info_list)
        responses["verification"] = client.product_info_list(product_ids: [product_id])
      end

      publication.update!(state: :completed, response_json: responses, completed_at: Time.current, last_error: nil)
      publication.reload
    rescue StandardError => error
      publication&.mark_failed!(message: error.message, response: {}) if publication&.persisted? && !error.is_a?(RawOzon::OzonClient::RetryableError)
      raise
    end
  end
end
