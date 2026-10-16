# frozen_string_literal: true

module AiEval
  # Produce editable drafts from a verified raw V3 baseline. No mapper fixture
  # is reconstructed or mislabeled as an original API snapshot.
  class SnapshotCaseTemplates
    def self.call(snapshot:, base_snapshot:)
      new(snapshot: snapshot, base_snapshot: base_snapshot).call
    end

    def initialize(snapshot:, base_snapshot:)
      @snapshot, @base_snapshot = snapshot, base_snapshot
    end

    def call
      snapshot.verify!
      {
        "stockout" => stockout,
        "missing_profit" => missing_profit,
        "clearance" => clearance
      }.transform_values { |definition| Case.from(definition) }
    end

    private

    attr_reader :snapshot, :base_snapshot

    def base(scenario)
      {
        "case_key" => "#{snapshot.sku_code.parameterize(separator: '_')}_#{scenario}",
        "version" => 1,
        "base_snapshot" => base_snapshot,
        "time_zone" => snapshot.manifest.time_zone,
        "scenario" => scenario,
        "review_status" => "draft",
        "date_mode" => { "type" => "none" },
        "derived_fields" => { "mode" => "preserve" },
        "patches" => [],
        "oracle" => {
          "diagnosis" => { "assertions" => [] },
          "planner" => { "assertions" => [] },
          "activepieces" => { "assertions" => [] }
        }
      }
    end

    def stockout
      definition = base("stockout")
      inventory = snapshot.read("v3/inventory_context.json").dig("data", "inventory", "current_inventory_info", "values")
      forecast = inventory&.fetch("strict_forecast_daily_sales", nil)
      unless forecast.is_a?(Numeric) && forecast.positive?
        raise Case::ValidationError, "stockout template requires a positive captured strict_forecast_daily_sales"
      end
      stock = [(forecast * 2).floor, 20].min
      definition["patches"] = [
        patch("v3/inventory_context.json", "/data/inventory/current_inventory_info/values/book_stock", stock),
        patch("v3/inventory_context.json", "/data/inventory/current_inventory_info/values/incoming_quantity", 0)
      ]
      definition["derived_fields"] = {
        "mode" => "recompute",
        "paths" => MaterializerDerivedFields::SUPPORTED_FIELDS.filter_map do |field|
          "#{MaterializerDerivedFields::PREFIX}#{field}" if inventory.key?(field)
        end
      }
      if snapshot.documents.key?("v3/lifecycle_context.json")
        summary = snapshot.read("v3/lifecycle_context.json").dig("data", "lifecycle", "summary", "values") || {}
        velocity = inventory["daily_sales_velocity"]
        if summary.key?("inventory_cover_days")
          cover = velocity.is_a?(Numeric) && velocity.positive? ? stock.to_f / velocity : nil
          definition["patches"] << patch("v3/lifecycle_context.json", "/data/lifecycle/summary/values/inventory_cover_days", cover)
        end
        if summary.key?("stockout_adjusted_inventory_cover_days") && summary["stockout_adjusted_daily_sales"].is_a?(Numeric)
          velocity = summary["stockout_adjusted_daily_sales"]
          cover = velocity.positive? ? stock.to_f / velocity : nil
          definition["patches"] << patch("v3/lifecycle_context.json", "/data/lifecycle/summary/values/stockout_adjusted_inventory_cover_days", cover)
        end
      end
      definition
    end

    def missing_profit
      definition = base("missing_profit")
      target = "v3/profit_context.json"
      periods = snapshot.read(target).dig("data", "profit", "sku_profit_overview_per_week", "periods")
      index = Array(periods).index { |period| period["period_key"] == "P-1" }
      raise Case::ValidationError, "missing-profit template requires a captured P-1 profit period" unless index
      definition["patches"] << { "target" => target, "op" => "remove", "path" => "/data/profit/sku_profit_overview_per_week/periods/#{index}" }
      # Remove the same week in listing rows and the shared period axis.  This
      # prevents the overview from claiming data is missing while listing data
      # quietly reintroduces it.
      listing = snapshot.read(target).dig("data", "profit", "sku_profit_store_listing_perweek") || {}
      Array(listing["periods"]).each_with_index.to_a.reverse_each do |(period, i)|
        definition["patches"] << { "target" => target, "op" => "remove", "path" => "/data/profit/sku_profit_store_listing_perweek/periods/#{i}" } if period["period_key"] == "P-1"
      end
      Array(listing["store_listings"]).each_with_index do |record, listing_index|
        Array(record["rows_per_week"]).each_with_index.to_a.reverse_each do |(period, i)|
          definition["patches"] << { "target" => target, "op" => "remove", "path" => "/data/profit/sku_profit_store_listing_perweek/store_listings/#{listing_index}/rows_per_week/#{i}" } if period["period_key"] == "P-1"
        end
      end
      definition
    end

    def clearance
      definition = base("clearance")
      definition["patches"] << patch("v3/base_context.json", "/data/base/current_stage", "CLR")
      if snapshot.documents.key?("v3/lifecycle_context.json")
        definition["patches"] << patch("v3/lifecycle_context.json", "/data/lifecycle/summary/values/current_stage", "clr")
      end
      definition
    end

    def patch(target, path, value)
      { "target" => target, "op" => "replace", "path" => path, "value" => value }
    end
  end
end
