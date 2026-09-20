module ErpAI
  class ToolRegistry
    JOINT_DIAGNOSIS_TOOL_DEFINITIONS = [
      {
        name: "create_sku_advise",
        description: "SKU 运营建议专用：为当前 SKU 创建一条新的运营建议事件，不会修改任何已有子规则事件。建议内容写入 message，scope 由系统固定为 advise。",
        parameters: {
          type: "object",
          properties: {
            sku_code: { type: "string", description: "内部 SKU code" },
            event_type: { type: "string", description: "具体建议操作的简写，使用中文且少于 10 个汉字" },
            severity: { type: "string", enum: %w[info warning critical], description: "建议执行紧迫程度" },
            message: { type: "string", description: "诊断依据和具体实施细节" }
          },
          required: %w[sku_code event_type severity message],
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
