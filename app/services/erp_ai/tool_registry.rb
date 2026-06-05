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
