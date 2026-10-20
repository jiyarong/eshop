module RawOzon
  class SupplyClient
    def initialize(account:, client: nil)
      @client = client || OzonClient.new(account.client_id, account.api_key)
    end

    def warehouses(query)
      post("/v1/warehouse/fbo/list", { filter_by_supply_type: ["CREATE_TYPE_CROSSDOCK"], search: query })
    end

    def create_draft(type:, cluster_id:, items:, drop_off: nil)
      body = { cluster_info: { macrolocal_cluster_id: cluster_id, items: items }, deletion_sku_mode: "FULL" }
      body[:delivery_info] = { type: "DROPOFF", drop_off_warehouse: drop_off } if type == "CROSSDOCK"
      post(type == "DIRECT" ? "/v1/draft/direct/create" : "/v1/draft/crossdock/create", body, write: true)
    end

    def draft_info(draft_id)
      post("/v2/draft/create/info", { draft_id: draft_id.to_i })
    end

    def timeslots(body)
      post("/v2/draft/timeslot/info", body)
    end

    def create_supply(body)
      post("/v2/draft/supply/create", body, write: true)
    end

    def supply_status(draft_id)
      post("/v2/draft/supply/create/status", { draft_id: draft_id.to_i })
    end

    def create_cargoes(supply_id:, cargoes:)
      post("/v1/cargoes/create", { supply_id: supply_id.to_i, cargoes: cargoes, delete_current_version: false }, write: true)
    end

    def cargoes_info(operation_id)
      post("/v2/cargoes/create/info", { operation_id: operation_id })
    end

    def cargoes_rules(supply_ids)
      post("/v1/cargoes/rules/get", { supply_ids: supply_ids.map(&:to_s) })
    end

    def bundle_items(bundle_id)
      items = []
      last_id = ""
      loop do
        response = post("/v1/supply-order/bundle", { bundle_ids: [bundle_id], limit: 100, last_id: last_id })
        items.concat(response.fetch("items"))
        break unless response["has_next"]
        cursor = response["last_id"].to_s
        raise OzonClient::ApiError, "Invalid Ozon bundle cursor" if cursor.blank? || cursor == last_id
        last_id = cursor
      end
      items
    end

    private

    def post(path, body, write: false)
      response = write ? @client.post(path, body, retry_on_error: false) : @client.post(path, body)
      raise OzonClient::ApiError, "Malformed Ozon response for #{path}" unless response.is_a?(Hash)
      response
    end
  end
end
