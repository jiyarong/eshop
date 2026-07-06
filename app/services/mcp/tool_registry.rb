module Mcp
  class ToolRegistry
    def initialize(current_user:)
      @current_user = current_user
    end

    def definitions
      [
        definition(
          "list_my_skus",
          "列出当前用户可运营的 SKU 及其店铺商品绑定。",
          {
            query: string_schema("按 SKU code 或商品名模糊搜索"),
            platform: enum_schema(%w[wb ozon], "平台筛选"),
            store_id: integer_schema("店铺 ID"),
            limit: integer_schema("返回数量，默认 50"),
            offset: integer_schema("偏移量，默认 0")
          }
        ),
        definition(
          "sku_sales",
          "查询单个 SKU 最近周期与上一周期的店铺销量对比。",
          {
            sku_code: string_schema("内部 SKU code"),
            period: enum_schema(%w[day week month 7d 30d], "周期，默认 week"),
            ended_on: string_schema("截止日期，ISO8601，默认当前用户时区今天")
          },
          required: ["sku_code"]
        ),
        definition(
          "sku_profile",
          "查询单个 SKU 的基础资料和平台商品绑定。",
          { sku_code: string_schema("内部 SKU code") },
          required: ["sku_code"]
        ),
        definition(
          "sku_inventory",
          "查询单个 SKU 的当前库存概览。",
          { sku_code: string_schema("内部 SKU code") },
          required: ["sku_code"]
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
