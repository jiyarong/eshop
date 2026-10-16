# frozen_string_literal: true

module AiEval
  class Snapshot < SnapshotPack
    SECTION_FILES = {
      "v3/base_context.json" => "base",
      "v3/inventory_context.json" => "inventory",
      "v3/lifecycle_context.json" => "lifecycle",
      "v3/profit_context.json" => "profit",
      "v3/sales_funnel_context.json" => "sales_funnel",
      "v3/advertising_context.json" => "advertise_per_week",
      "v3/orders_context.json" => "ec_orders_full_period",
      "v3/supply_orders_context.json" => "supply_orders_full_period",
      "v3/operation_actions_context.json" => "operation_actions_full_period",
      "v3/warehouse_recommendation_context.json" => "warehouse_recommendation",
      "v3/search_terms_context.json" => "search_terms_per_week"
    }.freeze
  end
end
