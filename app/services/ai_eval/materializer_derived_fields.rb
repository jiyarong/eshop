# frozen_string_literal: true

module AiEval
  class MaterializerDerivedFields
    INVENTORY_FILE = "v3/inventory_context.json".freeze
    PREFIX = "/data/inventory/current_inventory_info/values/".freeze
    SUPPORTED_FIELDS = %w[turnover_days turnover_days_with_procurement strict_forecast_cover_days].freeze

    def call(documents, definition)
      requested = Array(definition["paths"])
      invalid = requested - SUPPORTED_FIELDS.map { |field| "#{PREFIX}#{field}" }
      if invalid.any?
        raise Case::ValidationError, "unsupported derived field: #{invalid.join(', ')}"
      end
      return documents if requested.empty?

      values = documents.fetch(INVENTORY_FILE).dig("data", "inventory", "current_inventory_info", "values")
      raise Case::ValidationError, "inventory current values are missing" unless values.is_a?(Hash)
      stock = values["book_stock"]
      incoming = values["incoming_quantity"]
      velocity = values["daily_sales_velocity"]
      computed = if [stock, velocity].all? { |value| value.is_a?(Numeric) }
        # Reuse the same deterministic calculator used by inventory reports.
        Ec::InventoryReportRowMetricsBuilder.call(
          { book_stock: stock, incoming_quantity: incoming },
          metrics: { daily_sales_velocity: velocity }
        ).stringify_keys.tap do |result|
          result["turnover_days_with_procurement"] = nil unless incoming.is_a?(Numeric)
        end
      else
        { "turnover_days" => nil, "turnover_days_with_procurement" => nil }
      end
      forecast = values["strict_forecast_daily_sales"]
      # Same formula as InventoryPageDetailQuery#strict_forecast_metrics, without
      # rerunning the forecast model or any database query.
      computed["strict_forecast_cover_days"] = stock.is_a?(Numeric) && forecast.is_a?(Numeric) && forecast.positive? ? stock.to_d / forecast.to_d : nil
      requested.each do |path|
        field = path.delete_prefix(PREFIX)
        raise Case::ValidationError, "derived field is not present in snapshot: #{path}" unless values.key?(field)
        value = computed.fetch(field)
        values[field] = value.nil? ? nil : value.to_f
      end
      if requested.include?("#{PREFIX}strict_forecast_cover_days")
        strict = documents.fetch(INVENTORY_FILE).dig("data", "inventory", "current_inventory_info", "strict_forecast")
        strict["cover_days"] = values["strict_forecast_cover_days"] if strict.is_a?(Hash) && strict.key?("cover_days")
      end
      documents
    end
  end
end
