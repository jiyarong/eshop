# SKU context API schema

## Request

```http
GET /ai/v2/skus/full_context?sku_code=<SKU>&period_from=<MONDAY>&period_to=<SUNDAY>
Authorization: Bearer <assigned_user_api_key>
Accept: application/json
```

`period_from` and `period_to` are optional as a pair. The server returns `400` for missing required/paired parameters, `401` for invalid authorization, `404` for an unknown SKU, and `422` for invalid dates or natural-week boundaries.

## Response envelope

```json
{
  "data": {
    "sku_code": "SKU001",
    "period": {
      "from": "2026-08-24",
      "to": "2026-09-20"
    },
    "context": {}
  }
}
```

The returned period is the normalized context period. Context currently has five top-level keys.

## `base`

Date-independent SKU master data:

- `spu_code`: parent SPU code, or `null`.
- `spu_id`: parent SPU database ID, or `null`.
- `related_spu_sku_codes`: sibling SKU codes under the same SPU, excluding the requested SKU.
- `current_stage`: current marketing stage, such as `NEW`, `GRW`, `MAT`, or `CLR`.
- `current_grade`: current marketing grade, such as `S`, `A`, `B`, or `C`.
- `sku_products`: platform bindings. Each item contains `store_id`, `platform`, `product_id`, and `offer_id`.

## `weekly_profit_per_week`

Contains `wr`, `wsu`, and `wsu_deep` arrays. Each array has one item per completed natural week. This section always shifts the requested window back one week so unfinished current-week profit is excluded.

- Every week contains `period_from` and `period_to`.
- `wsu[].data` contains the existing WSU list rows, grouped by SKU, platform, and shop.
- `wsu_deep[].data` contains the existing WSU-DEEP list rows, aggregated by SKU with profit and ROI metrics.
- `wr[]` contains `stores`; each store has `store_ref`, `platform`, `store_id`, `store_name`, and `data`.
- WB and Ozon WR rows intentionally have different platform-native fields.
- Comparison data is not requested or returned because the response already contains N individual weeks.

## `sales_funnel_per_week`

An array using the requested period without the profit section's one-week shift:

```text
week -> stores -> data rows
```

Each week contains `period_from`, `period_to`, and `stores`. Each store contains `store_ref`, `platform`, `store_id`, `store_name`, and `data`. Data comes from the daily funnel report aggregated into that natural week and filtered to the requested SKU. WB and Ozon rows intentionally have different fields. Comparison data is not requested or returned.

The current week's row is partial through the latest synchronized day; future days in that natural week have no data yet.

## `current_inventory_info`

Current inventory information calculated as of today in the API user's time zone. It does not use the requested period.

- `list`: the same single-SKU list metrics produced by the inventory report.
- `detail`: the same single-SKU detail payload produced by the inventory report.

Preserve all returned fields because inventory report fields may evolve.

## `history_inventory_info`

Inventory snapshots for the requested SKU and period, ordered by date:

```json
[
  {
    "snapshot_date": "2026-09-01",
    "content": {}
  }
]
```

These records come from `ec_snapshots` where `snapshot_type = inventory` and `sku_id` matches the requested SKU. `content` is returned without field reduction.
