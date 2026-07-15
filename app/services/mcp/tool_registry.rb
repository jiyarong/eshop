module Mcp
  class ToolRegistry
    def initialize(current_user:)
      @current_user = current_user
    end

    def definitions
      [
        # definition(
        #   "list_my_skus",
        #   "列出当前用户可运营的 SKU 及其店铺商品绑定。",
        #   {
        #     query: string_schema("按 SKU code 或商品名模糊搜索"),
        #     platform: enum_schema(%w[wb ozon], "平台筛选"),
        #     store_id: integer_schema("店铺 ID"),
        #     limit: integer_schema("返回数量，默认 50"),
        #     offset: integer_schema("偏移量，默认 0")
        #   }
        # ),
        # definition(
        #   "sku_sales",
        #   "查询单个 SKU 最近周期与上一周期的店铺销量对比。",
        #   {
        #     sku_code: string_schema("内部 SKU code"),
        #     period: enum_schema(%w[day week month 7d 30d], "周期，默认 week"),
        #     ended_on: string_schema("截止日期，ISO8601，默认当前用户时区今天")
        #   },
        #   required: ["sku_code"]
        # ),
        # definition(
        #   "sku_profile",
        #   "查询单个 SKU 的基础资料和平台商品绑定。",
        #   { sku_code: string_schema("内部 SKU code") },
        #   required: ["sku_code"]
        # ),
        # definition(
        #   "sku_inventory",
        #   "查询单个 SKU 的当前库存概览。",
        #   { sku_code: string_schema("内部 SKU code") },
        #   required: ["sku_code"]
        # ),
        # definition(
        #   "ozon_cluster_sales_distribution",
        #   "查询 Ozon 销量在发货集群和目的集群之间的分布矩阵，可用于分析跨集群销售和本地销售。",
        #   {
        #     from_date: string_schema("开始日期，ISO8601，例如 2026-06-30；默认当前用户时区最近 14 天"),
        #     to_date: string_schema("结束日期，ISO8601，例如 2026-07-13；默认当前用户时区今天"),
        #     store_id: integer_schema("Ozon 店铺 ID，可选"),
        #     sku_code: string_schema("内部 SKU code，可选"),
        #     query: string_schema("按 SKU code、商品名或订单商品名模糊搜索，可选"),
        #     fulfillment_type: enum_schema(%w[fbo fbs], "Ozon 履约模式，可选"),
        #     order_status: string_schema("订单状态，逗号分隔；默认包含全部状态，例如 shipped,delivered"),
        #     limit: integer_schema("返回矩阵 cell 数量，默认 100，最大 500"),
        #     offset: integer_schema("矩阵 cell 偏移量，默认 0")
        #   }
        # ),
        # definition(
        #   "ozon_sku_localization",
        #   "查询 Ozon SKU 的本地化销售占比：发货集群等于目的集群的销量 / 总销量。",
        #   {
        #     from_date: string_schema("开始日期，ISO8601，例如 2026-06-30；默认当前用户时区最近 14 天"),
        #     to_date: string_schema("结束日期，ISO8601，例如 2026-07-13；默认当前用户时区今天"),
        #     store_id: integer_schema("Ozon 店铺 ID，可选"),
        #     sku_code: string_schema("内部 SKU code，可选"),
        #     query: string_schema("按 SKU code、商品名或订单商品名模糊搜索，可选"),
        #     fulfillment_type: enum_schema(%w[fbo fbs], "Ozon 履约模式，可选"),
        #     order_status: string_schema("订单状态，逗号分隔；默认包含全部状态，例如 shipped,delivered"),
        #     sort: enum_schema(%w[total_quantity localization_rate non_local_quantity local_quantity sku_code], "排序字段，默认 total_quantity"),
        #     limit: integer_schema("返回 SKU 数量，默认 50，最大 200"),
        #     offset: integer_schema("SKU 偏移量，默认 0")
        #   }
        # ),
        definition(
          "sql_query",
          "执行只读 SQL 查询。仅允许单条 SELECT 或 WITH 查询，必须明确指定返回列。",
          {
            sql: string_schema("要执行的只读 SQL"),
            limit: integer_schema("返回数量，默认 100，最大 500"),
            offset: integer_schema("偏移量，默认 0")
          },
          required: ["sql"]
        ),
        definition(
          "operation_context",
          "返回当前用户、时区、权限和可用数据范围。",
          {}
        )
      ]
    end

    private

    attr_reader :current_user

    def definition(name, description, properties, required: [])
      {
        name: name,
        description: description,
        inputSchema: {
          type: "object",
          properties: properties,
          required: required
        }
      }
    end

    def string_schema(description)
      { type: "string", description: description }
    end

    def integer_schema(description)
      { type: "integer", description: description }
    end

    def enum_schema(values, description)
      { type: "string", enum: values, description: description }
    end
  end
end
