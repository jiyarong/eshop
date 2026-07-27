module ErpAI
  class ToolRegistry
    TOOL_DEFINITIONS = [
      {
        name: "query_sales_data",
        description: "查询销售额、订单量、商品、区域和时间趋势等 ERP 销售数据。"
      },
      {
        name: "query_inventory_data",
        description: "查询库存数量、库存金额、周转率、库龄、缺货和积压情况。"
      },
      {
        name: "query_purchase_data",
        description: "查询采购订单、供应商、采购价格和到货及时率。"
      },
      {
        name: "query_finance_data",
        description: "查询收入、成本、毛利、应收应付和回款情况。"
      },
      {
        name: "query_business_object",
        description: "查询订单、客户、商品、供应商或仓库等业务对象详情。"
      },
      {
        name: "erp_ai_request",
        description: "调用当前应用内指定路径对应的 ErpAI Controller。仅允许 app-relative /ai/... URL，不允许外部 host。",
        parameters: {
          type: "object",
          properties: {
            method: {
              type: "string",
              enum: %w[get post put patch delete],
              description: "HTTP method，默认 get"
            },
            url: {
              type: "string",
              description: "App-relative URL，例如 /ai/weekly_profit_reports.json"
            },
            params: {
              type: "object",
              description: "请求参数。GET/DELETE 作为 query string，POST/PUT/PATCH 作为 JSON body",
              additionalProperties: true
            },
            headers: {
              type: "object",
              description: "可转发的 HTTP headers，仅接受 Accept、Accept-Language、X-Request-Id",
              additionalProperties: true
            }
          },
          required: [ "url" ],
          additionalProperties: false
        }
      }
    ].freeze

    def self.default_tools
      TOOL_DEFINITIONS
    end

    def self.default_tool_names
      TOOL_DEFINITIONS.map { |tool| tool.fetch(:name) }
    end
  end
end
