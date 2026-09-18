module ErpAI
  class ToolRegistry
    JOINT_DIAGNOSIS_TOOL_DEFINITIONS = [
      {
        name: "update_sku_diagnosis_event",
        description: "联合诊断专用：按事件 ID 修正当前 SKU 子规则事件的严重级别、AI 建议，或将事件标记为 ignored。只有确有必要时才调用；不传 advise 时保留原建议。",
        parameters: {
          type: "object",
          properties: {
            sku_code: { type: "string", description: "内部 SKU code" },
            event_id: { type: "integer", description: "要调整的诊断事件 ID" },
            severity: { type: "string", enum: %w[info warning critical], description: "新的事件严重级别，可选" },
            advise: { type: "string", description: "新的建议，可选；传入后必须以 AI： 开头" },
            status: { type: "string", enum: %w[ignore ignored], description: "传 ignore 或 ignored 将事件标记为 ignored，可选" }
          },
          required: %w[sku_code event_id],
          additionalProperties: false
        }
      }
    ].freeze

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
      },
      {
        name: "save_sku_event",
        description: "保存当前 SKU 的诊断事件。同一 SKU、同一子规则（最终联合诊断为空）、同一天的结果会覆盖之前的记录。",
        parameters: {
          type: "object",
          properties: {
            sku_code: { type: "string", description: "内部 SKU code" },
            sub_agent_id: { type: [ "integer", "null" ], description: "SKU 诊断规则 ID；最终联合诊断必须传 null" },
            event_type: { type: "string", description: "诊断事件类型" },
            severity: { type: "string", description: "事件严重级别" },
            message: { type: "string", description: "诊断结果和依据" },
            advise: { type: "string", description: "操作建议" }
          },
          required: %w[sku_code sub_agent_id event_type severity message advise],
          additionalProperties: false
        }
      }
    ].freeze

    def self.default_tools
      TOOL_DEFINITIONS
    end

    def self.joint_diagnosis_tools
      JOINT_DIAGNOSIS_TOOL_DEFINITIONS
    end

    def self.default_tool_names
      TOOL_DEFINITIONS.map { |tool| tool.fetch(:name) } - ["save_sku_event"]
    end
  end
end
