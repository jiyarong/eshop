# Inventory Procurement API Skill

用于回答库存列表、库存搜索、账面库存、FBS 库存、平台在库、平台在途、周转天数、补货和库存详情页相关问题。

## 强制调用业务 API

库存报表相关问题统一调用 `POST /ai/inventory_reports.json`。该接口复用库存报表列表页和详情页的业务逻辑，一次返回当前页每个 SKU 的列表数据与完整详情数据。

```http
POST /ai/inventory_reports.json
Authorization: Bearer <user_api_key>
Content-Type: application/json

{
  "sku": "ABC",
  "page": 1,
  "detail_tab": "incoming",
  "book_batch_page": 1
}
```

## 请求参数

库存页面筛选参数：

- `sku`：按 SKU code 模糊搜索。
- `master_sku_ids` / `master_sku_id`、`sku_codes`：SPU/SKU 组合筛选。
- `category_ids` / `category_id`：SPU 类目筛选。
- `grades` / `grade`、`stages` / `stage`：当前营销状态筛选。
- `operator_id`、`developer_id`：负责人筛选。
- `turnover_days_min`、`turnover_days_max`：账面库存周转天数区间。
- `procurement_turnover_days_min`、`procurement_turnover_days_max`：包含采购中库存的周转天数区间。

分页与详情参数：

- `page`、`current_page`、`jump_page`：库存列表分页，优先级与库存页面一致，每页 10 个 SKU。
- `detail_tab`：详情页默认激活的板块，可选 `incoming`、`book`、`platform`；不传或传入无效值时默认为 `incoming`。
- `book_batch_page`：账面库存板块里的批次分页页码，每页 10 条；不传时默认为第 1 页。

## detail_tab 板块含义

`detail_tab` 用于表示库存详情页默认展开哪个板块：

- `incoming`：在途库存板块。关注采购中/运输中的批次、预计到货日期、采购数量和备注；主要使用 `incoming_quantity`、`incoming_batches`。
- `book`：账面库存板块。关注账面库存组成、已到货批次、销售与退货分布、账面库存计算公式；主要使用 `book_batches`、`book_batch_pagination`、`book_mini_stats`、`book_sales_distribution`、`return_distribution`、`book_formula`。
- `platform`：平台库存板块。关注 WB/Ozon 平台仓现货、平台在途、店铺拆分、仓库拆分、平台库存计算公式及店铺对账；主要使用 `platform_mini_stats`、`platform_shop_rows`、`platform_shop_summary_row`、`platform_formula`、`platform_warehouse_rows`、`store_reconciliation_rows`、`platform_breakdown`。

不同的 `detail_tab` 会产生不同的 `detail.active_detail_tab` 值，用于标识详情页默认展示板块。除此之外，当前接口不会按 `detail_tab` 分支查询或裁剪字段：`incoming`、`book`、`platform` 三个板块的数据始终同时返回。回答用户问题时，应从对应板块字段中选取需要的数据，不要无差别输出全部详情。

## 响应结构

```json
{
  "success": true,
  "data": {
    "volume_summary": {},
    "rows": [
      { "list": {}, "detail": {} }
    ],
    "pagination": {
      "page": 1,
      "page_size": 10,
      "total_count": 1,
      "total_pages": 1,
      "has_more": false,
      "next_page": null
    }
  },
  "message": "ok"
}
```

- `data.volume_summary`：当前全部筛选结果的库存体积汇总，不只统计当前页。
- `data.rows[].list`：与库存报表列表行一致的字段。
- `data.rows[].detail`：同一 SKU 的完整详情数据。
- `data.pagination`：SKU 列表分页信息。
- `data.rows[].detail.book_batch_pagination`：该 SKU 的账面批次分页信息。

需要下一页 SKU 时修改列表页参数；需要下一页账面批次时修改 `book_batch_page`。

## 使用原则

- 用户问“库存列表”“查某个 SKU 库存”“库存小于/大于多少”“周转天数筛选”时，主要读取 `list`。
- 用户问采购中库存、在途批次或预计到货时，使用 `detail_tab: "incoming"`，主要读取在途库存板块字段。
- 用户问账面批次、销量、退货或账面库存组成时，使用 `detail_tab: "book"`，主要读取账面库存板块字段。
- 用户问平台库存、店铺拆分、平台仓库或平台在途时，使用 `detail_tab: "platform"`，主要读取平台库存板块字段。
- 用户只说“库存”“可用库存”“还有多少”且口径不明确时，先问清楚是账面库存、报表 FBS 库存、平台在库、平台在途，还是平台侧 FBS 库存。
- 用户只说“补货”“需要补多少”“补到多少天周转”时，先问清楚是补平台库 FBO/FBW，还是补账面库存/报表 FBS 库存。
- 列表固定每页 10 个 SKU，必须根据 `pagination.has_more` 和 `pagination.next_page` 继续翻页。

## 库存字段口径

- `incoming_quantity`：采购中库存数量。
- `book_stock`：账面可用库存，即已到货数量扣除有效销量后加回有效退货数量。
- `platform_inbound_stock`：平台在途/入库数量。
- `platform_stock`：WB FBW 与 Ozon FBO 等平台仓现货数量。
- `available_stock`：报表 FBS 库存，即账面库存扣除平台仓现货和平台在途后的内部可用库存。
- `daily_sales_velocity`：最近 7/15/30 天的加权日销。
- `turnover_days`：账面库存对应的周转天数。
- `turnover_days_with_procurement`：账面库存加采购中库存对应的周转天数。
- `pkg_length_cm`、`pkg_width_cm`、`pkg_height_cm`、`unit_volume_l`：包装尺寸和单件体积；需要进一步做包装或体积测算时加载 `sku_dimensions` Skill。

报表里的 `available_stock` 与平台侧 FBS 库存不是同一个口径。用户在库存报表上下文中只说“FBS库存”时，默认指 `available_stock`；用户明确问平台侧 FBS 快照或卖家自仓可发库存时，读取平台详情中的 FBS 字段。

## 周转筛选

- 四个周转上下限参数可以组合使用，多个条件之间是 AND。
- 某个上下限为空时，该方向不限制。
- 对应周转指标为空的 SKU 不匹配已设置的周转条件。
- 日销小于等于 0 时，两个周转指标为空。
- 负数周转天数默认不匹配非负下限；只有明确传入负数下限时，负数才参与匹配。

## 补货问题

- 补平台库：目标是平台仓现货，WB 看 FBW，Ozon 看 FBO；关注 `platform_stock`、`platform_inbound_stock` 和平台库存详情。
- 补账面库存或报表 FBS 库存：目标是内部库存；关注 `book_stock`、`available_stock`、`incoming_quantity`、`turnover_days_with_procurement`。
- 补平台库是把已有或将有的库存送到平台仓；补账面库存表示内部库存总量不足，需要采购、到货或调整。两者不能混用。
- 用户没有说清楚补货目标时，不要直接计算补货量。
