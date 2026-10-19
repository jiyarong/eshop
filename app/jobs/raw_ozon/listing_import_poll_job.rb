module RawOzon
  class ListingImportPollJob < ApplicationJob
    queue_as :default
    MAX_POLLS = 30

    def perform(publication_id)
      publication = Ec::OzonListingPublication.find(publication_id)
      return publication unless publication.pending?

      response = RawOzon::ListingClient.for_account(publication.account).import_info(publication.ozon_task_id)
      status = task_status(response)
      items = task_items(response)

      case status
      when "pending", "processing", "in_progress", "running"
        publication.increment!(:attempts)
        if publication.attempts.to_i >= MAX_POLLS
          publication.mark_failed!(message: "Ozon import polling timed out", errors: normalize_errors(items))
        else
          self.class.set(wait: 30.seconds).perform_later(publication.id)
        end
      when "imported", "success", "completed", "done"
        reconcile_import(publication, response, items)
      when "failed", "error"
        publication.mark_failed!(message: "Ozon import failed", errors: normalize_errors(items), response: response)
      when "skipped"
        publication.update!(state: :skipped, error_details: normalize_errors(items), response_json: response, completed_at: Time.current)
      else
        publication.mark_failed!(message: "Unknown Ozon import state: #{status.presence || "missing"}", errors: normalize_errors(items), response: response)
      end

      publication.reload
    rescue StandardError => error
      publication&.mark_failed!(message: error.message, response: {}) if publication&.persisted? && !error.is_a?(RawOzon::OzonClient::RetryableError)
      raise
    end

    private

    def task_status(response)
      value = response["status"] || response.dig("result", "status") || response.dig("result", "state")
      value.to_s.downcase
    end

    def task_items(response)
      Array(response["items"] || response.dig("result", "items") || response["products"] || response.dig("result", "products"))
    end

    def normalize_errors(items)
      Array(items).filter_map do |item|
        item = item.is_a?(Hash) ? item : { "message" => item.to_s }
        raw = item["errors"] || item["error"] || item["validation_errors"]
        Array(raw).map do |error|
          error = error.is_a?(Hash) ? error : { "message" => error.to_s }
          {
            "code" => error["code"] || error["error_code"],
            "field" => error["field"],
            "attribute_id" => error["attribute_id"],
            "level" => error["level"],
            "message" => error["message"] || error["error_message"] || error.to_s
          }.compact
        end
      end.flatten
    end

    def reconcile_import(publication, response, items)
      product_ids = Array(items).filter_map { |item| item["product_id"] || item["id"] || item.dig("product", "id") }.compact
      product_ids = [response["product_id"] || response.dig("result", "product_id")].compact if product_ids.empty?
      if product_ids.empty?
        publication.mark_failed!(message: "Ozon import completed without product_id", errors: normalize_errors(items), response: response)
        return
      end

      info_response = RawOzon::ListingClient.for_account(publication.account).product_info_list(product_ids: product_ids)
      products = Array(info_response["items"] || info_response.dig("result", "items"))
      product = products.find { |item| item["id"].to_s == product_ids.first.to_s } || products.first
      unless product && product["id"].present?
        publication.mark_failed!(message: "Ozon product read-back returned no product", response: info_response)
        return
      end
      validation_errors = product["validation_errors"] || product["errors"]
      if product["is_created"].to_s == "false" || validation_errors.present?
        publication.mark_failed!(message: "Ozon product is not ready after read-back", errors: normalize_errors([product]), response: info_response)
        return
      end

      return unless bind_product(publication, product, info_response)
      publication.update!(
        state: :ready_for_price_stock,
        product_id: product["id"].to_s,
        platform_sku_id: (product["sku"] || product["platform_sku_id"]).to_s.presence,
        response_json: response.merge("read_back" => info_response),
        completed_at: Time.current
      )
    end

    def bind_product(publication, product, info_response)
      store = publication.store
      product_id = product["id"].to_s
      platform_sku_id = (product["sku"] || product["platform_sku_id"]).to_s.presence
      existing = Ec::SkuProduct.find_by(store_id: store.id, product_id: product_id)
      if existing && existing.sku_code.present? && existing.sku_code != publication.sku_code
        publication.mark_failed!(message: "Ozon product is already bound to another SKU", response: product)
        return false
      end
      before = existing&.attributes&.slice("product_id", "platform_sku_id", "offer_id", "product_name")
      binding = existing || Ec::SkuProduct.new(store: store, platform: "ozon", product_id: product_id)
      binding.assign_attributes(
        sku_code: publication.sku_code,
        offer_id: publication.offer_id,
        platform_sku_id: platform_sku_id,
        product_name: product["name"] || product["title"],
        is_active: true
      )
      binding.save!
      RawOzon::Product.where(account_id: publication.account_id, ozon_product_id: product_id.to_i).first_or_initialize.tap do |raw|
        raw.assign_attributes(product_fields(product, publication.account_id, publication.offer_id))
        raw.save!
      end
      attributes = product["attributes"] || product["product_attributes"]
      if attributes || product["complex_attributes"]
        RawOzon::ProductAttribute.where(account_id: publication.account_id, ozon_product_id: product_id.to_i).first_or_initialize.tap do |raw|
          raw.assign_attributes(
            offer_id: product["offer_id"] || publication.offer_id,
            product_attributes: Array(attributes),
            complex_attributes: Array(product["complex_attributes"]),
            barcode: product["barcode"],
            raw_json: product,
            synced_at: Time.current
          )
          raw.save!
        end
      end
      return true unless existing && before

      Ec::ListingChangeRecorder.record(
        sku_product: binding,
        operation_type: "listing_content",
        before: before,
        after: binding.attributes.slice("product_id", "platform_sku_id", "offer_id", "product_name")
      )
      true
    end

    def product_fields(product, account_id, offer_id)
      {
        account_id: account_id,
        ozon_product_id: product["id"].to_i,
        offer_id: product["offer_id"] || offer_id,
        name: product["name"],
        description_category_id: product["description_category_id"],
        type_id: product["type_id"],
        currency_code: product["currency_code"],
        is_archived: product["is_archived"] || false,
        is_autoarchived: product["is_autoarchived"] || false,
        barcodes: Array(product["barcodes"]),
        images: product["images"],
        images360: product["images360"],
        color_image: product["color_image"],
        commissions: product["commissions"],
        availabilities: product["availabilities"],
        raw_json: product,
        synced_at: Time.current
      }
    end

  end
end
