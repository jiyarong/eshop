# SKU v3 上下文 API

v3 将原来的完整上下文拆成多个小接口。所有接口共享参数：

| 参数 | 必填 | 说明 |
| --- | --- | --- |
| `sku_code` | 是 | 内部 SKU 编码，不区分输入大小写 |
| `period_from` | 否 | 查询周期开始日；传入时必须是周一 |
| `period_to` | 否 | 查询周期结束日；传入时必须是周日 |
| `target_days` | 否 | 仅分仓建议使用，表示建议覆盖天数 |

脚本默认请求 Markdown 格式：

```http
GET /ai/v3/sku/<section>_context.md?sku_code=<SKU>&period_from=<MONDAY>&period_to=<SUNDAY>
Authorization: Bearer <assigned_user_api_key>
Accept: text/markdown
```

可请求的分段接口与本地文件：

| 本地文件 | 接口 | 上下文键 |
| --- | --- | --- |
| `base.md` | `/ai/v3/sku/base_context.md` | `base` |
| `sales_funnel.md` | `/ai/v3/sku/sales_funnel_context.md` | `sales_funnel` |
| `profit.md` | `/ai/v3/sku/profit_context.md` | `profit` |
| `inventory.md` | `/ai/v3/sku/inventory_context.md` | `inventory` |
| `lifecycle.md` | `/ai/v3/sku/lifecycle_context.md` | `lifecycle` |
| `advertise_per_week.md` | `/ai/v3/sku/advertising_context.md` | `advertise_per_week` |
| `ec_orders_full_period.md` | `/ai/v3/sku/orders_context.md` | `ec_orders_full_period` |
| `supply_orders_full_period.md` | `/ai/v3/sku/supply_orders_context.md` | `supply_orders_full_period` |
| `operation_actions_full_period.md` | `/ai/v3/sku/operation_actions_context.md` | `operation_actions_full_period` |
| `warehouse_recommendation.md` | `/ai/v3/sku/warehouse_recommendation_context.md` | `warehouse_recommendation` |
| `search_terms_per_week.md` | `/ai/v3/sku/search_terms_context.md` | `search_terms_per_week` |

完整接口 `/ai/v3/sku/full_context.md` 仍可用于一次性获取全部上下文，但默认应使用分段接口，避免单个请求过慢。
