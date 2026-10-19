module RawOzon
  class ListingClient
    MAX_IMPORT_ITEMS = 100

    def self.for_account(account)
      new(account: account)
    end

    def initialize(account:, client: nil)
      @account = account
      @client = client || OzonClient.new(account.client_id, account.api_key)
    end

    attr_reader :account, :client

    def last_response_headers
      client.respond_to?(:last_response_headers) ? client.last_response_headers : {}
    end

    def import_products(items, request_id: nil)
      items = normalize_items(items)
      raise ArgumentError, "Ozon import accepts at most #{MAX_IMPORT_ITEMS} items" if items.length > MAX_IMPORT_ITEMS

      post("/v3/product/import", { items: items }, request_id: request_id)
    end

    alias import import_products
    alias import_product import_products

    def import_info(task_id, request_id: nil)
      post("/v1/product/import/info", { task_id: task_id }, request_id: request_id)
    end

    alias import_status import_info

    def update_attributes(items, request_id: nil)
      post("/v1/product/attributes/update", { items: normalize_items(items) }, request_id: request_id)
    end

    alias attribute_update update_attributes

    def import_pictures(product_id:, images:, primary_image: nil, color_image: nil, request_id: nil)
      body = { product_id: product_id, images: normalize_items(images) }
      body[:primary_image] = primary_image if primary_image.present?
      body[:color_image] = color_image if color_image.present?
      post("/v2/product/pictures/import", body, request_id: request_id)
    end

    alias pictures_import import_pictures

    def picture_info(product_id:, request_id: nil)
      post("/v2/product/pictures/info", { product_id: product_id }, request_id: request_id)
    end

    alias pictures_info picture_info

    def import_prices(items, request_id: nil)
      post("/v1/product/import/prices", { items: normalize_items(items) }, request_id: request_id)
    end

    alias prices_update import_prices

    def update_stocks(stocks, request_id: nil)
      post("/v2/products/stocks", { stocks: normalize_items(stocks) }, request_id: request_id)
    end

    alias stocks_update update_stocks

    def product_info_list(product_ids: nil, product_id: nil, request_id: nil)
      ids = product_ids || product_id
      post("/v3/product/info/list", { product_id: normalize_items(ids) }, request_id: request_id)
    end

    alias product_info product_info_list

    def quota(request_id: nil)
      post("/v4/product/info/limit", {}, request_id: request_id)
    end

    alias product_limit quota

    def roles(request_id: nil)
      post("/v1/roles", {}, request_id: request_id)
    end

    private

    def normalize_items(value)
      return value[:items] || value["items"] if value.is_a?(Hash) && (value.key?(:items) || value.key?("items"))
      return [value] if value.is_a?(Hash)

      Array(value)
    end

    def post(path, body, request_id: nil)
      response = if request_id.present?
        client.post(path, body, headers: { "X-Request-Id" => request_id })
      else
        client.post(path, body)
      end
      raise OzonClient::ApiError, "Malformed Ozon response for #{path}" unless response.is_a?(Hash)

      response
    end
  end
end
