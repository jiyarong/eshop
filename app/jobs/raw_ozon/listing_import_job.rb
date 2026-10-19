module RawOzon
  class ListingImportJob < ApplicationJob
    queue_as :default

    def perform(publication_id)
      publication = Ec::OzonListingPublication.find(publication_id)
      return publication if publication.pending? || publication.imported? || publication.completed?
      return publication unless publication.confirmed? || publication.queued?

      publication.queue! if publication.confirmed?
      publication.with_lock do
        next if publication.pending? || publication.imported? || publication.completed?

        client = RawOzon::ListingClient.for_account(publication.account)
        if client.respond_to?(:quota)
          quota = client.quota
          raise RawOzon::OzonClient::ApiError, "Ozon product quota is exhausted" if quota_exhausted?(quota)
        end
        items = [import_item(publication)]
        response = if publication.request_id.present?
          client.import_products(items, request_id: publication.request_id)
        else
          client.import_products(items)
        end
        task_id = response["task_id"] || response.dig("result", "task_id") || response["id"]
        raise RawOzon::OzonClient::ApiError, "Ozon import response has no task_id" if task_id.blank?

        headers = client.respond_to?(:last_response_headers) ? client.last_response_headers : {}
        request_id = publication.request_id.presence || headers.to_h["request_id"]
        publication.mark_pending!(task_id:, response:, request_id: request_id)
      end
      RawOzon::ListingImportPollJob.perform_later(publication.id)
      publication.reload
    rescue StandardError => error
      publication&.mark_failed!(message: error.message, response: {}) if publication&.persisted? && !error.is_a?(RawOzon::OzonClient::RetryableError)
      raise
    end

    private

    def quota_exhausted?(response)
      result = response.to_h["result"].to_h
      limit = result["limit"] || result["items_limit"] || response.to_h["limit"]
      used = result["used"] || result["items_used"] || response.to_h["used"]
      remaining = result["remaining"] || result["items_remaining"] || response.to_h["remaining"]
      return remaining.to_i <= 0 if remaining.present?
      limit.present? && used.present? && used.to_i >= limit.to_i
    end

    def import_item(publication)
      payload = publication.payload.to_h.deep_symbolize_keys
      item = payload[:item] || payload[:import_item]
      return item if item.is_a?(Hash)
      return Array(payload[:items]).first if payload[:items].present?

      dimensions = payload[:dimensions].to_h
      {
        offer_id: payload[:offer_id],
        name: payload[:name],
        description: payload[:description],
        category_id: payload.dig(:category, :description_category_id),
        type_id: payload.dig(:category, :type_id),
        barcode: Array(payload[:barcodes]).first,
        barcodes: Array(payload[:barcodes]),
        depth: dimensions[:depth] || dimensions[:length],
        width: dimensions[:width],
        height: dimensions[:height],
        dimension_unit: dimensions[:unit] || "mm",
        weight: payload[:weight],
        weight_unit: payload[:weight_unit] || "g",
        vat: payload[:vat],
        currency_code: payload[:currency_code],
        attributes: Array(payload[:attributes]),
        complex_attributes: Array(payload[:complex_attributes]),
        images: Array(payload[:images]),
        primary_image: payload[:primary_image],
        color_image: payload[:color_image],
        price: payload.dig(:price, :price),
        old_price: payload.dig(:price, :old_price),
        min_price: payload.dig(:price, :min_price)
      }.compact
    end
  end
end
