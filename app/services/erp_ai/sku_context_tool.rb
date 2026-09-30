module ErpAI
  class SkuContextTool
    SECTION_PATHS = {
      "base" => "/ai/v3/sku/base_context",
      "inventory" => "/ai/v3/sku/inventory_context",
      "lifecycle" => "/ai/v3/sku/lifecycle_context",
      "profit" => "/ai/v3/sku/profit_context",
      "sales_funnel" => "/ai/v3/sku/sales_funnel_context",
      "advertise_per_week" => "/ai/v3/sku/advertising_context",
      "ec_orders_full_period" => "/ai/v3/sku/orders_context",
      "supply_orders_full_period" => "/ai/v3/sku/supply_orders_context",
      "operation_actions_full_period" => "/ai/v3/sku/operation_actions_context",
      "warehouse_recommendation" => "/ai/v3/sku/warehouse_recommendation_context",
      "search_terms_per_week" => "/ai/v3/sku/search_terms_context"
    }.freeze

    def initialize(current_user:, request_client: ::Mcp::ErpAIRequest)
      @current_user = current_user
      @request_client = request_client
      @visible_scope = ::Mcp::VisibleSkuScope.new(current_user)
    end

    def call(arguments)
      return { error: "current user is required" } unless current_user

      sku_code = arguments["sku_code"].to_s.strip.upcase
      return { error: "sku_code is required" } if sku_code.blank?

      context_module = arguments["module"].to_s.strip
      return { error: "module is required" } if context_module.blank?
      return { error: "module is invalid" } unless SECTION_PATHS.key?(context_module)

      sku = visible_sku(sku_code)
      return { error: "SKU is not visible to current user" } unless sku

      response = request_client.new(current_user: current_user).call(
        "method" => "get",
        "url" => SECTION_PATHS.fetch(context_module),
        "params" => { "sku_code" => sku.sku_code },
        "headers" => { "Accept" => "text/markdown" }
      )
      return response unless response[:success]

      {
        sku_code: sku.sku_code,
        module: context_module,
        description: Ec::SkuContextSnapshot.context_descriptions.fetch(context_module.to_sym),
        markdown: response.fetch(:body).to_s
      }
    end

    private

    attr_reader :current_user, :request_client, :visible_scope

    def visible_sku(sku_code)
      return Ec::Sku.find_by(sku_code: sku_code) if visible_scope.global_user?
      return unless visible_scope.sku_codes.include?(sku_code)

      Ec::Sku.find_by(sku_code: sku_code)
    end
  end
end
