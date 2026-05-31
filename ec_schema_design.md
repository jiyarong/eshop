# ec_* 核心数据库设计

> 目标：以 `master_sku`（`ec_skus.sku_code`）为核心，聚合各电商平台的销售、库存、财务、漏斗数据，并管理每个 SKU 的成本结构。

---

## 一、整体设计原则

| 原则 | 说明 |
|------|------|
| `master_sku` 是轴心 | 所有 ec_* 表通过 `ec_sku_id` 关联，跨平台比较的基础 |
| 平台差异屏蔽在 ETL | ec_* 表不感知 WB/Ozon 的字段差异，统一字段命名 |
| 保留溯源字段 | 每行保留 `platform` + `external_id`，可回查 raw 数据 |
| 时序数据按粒度拆分 | 日维度快照 / 月维度汇总 / 明细流水 分开建表，查询效率优先 |
| 成本表独立 | 成本数据来自内部录入，不来自任何平台，独立管理 |

---

## 二、核心身份层（2 张表）

### `ec_products` — 主商品

```sql
create_table :ec_products do |t|
  t.string   :internal_code,   null: false   -- 公司内部商品编码，唯一
  t.string   :name,            null: false   -- 商品名称
  t.string   :category                       -- 内部分类
  t.text     :description
  t.jsonb    :meta,            default: {}   -- 扩展字段（图片、材质等）
  t.timestamps
end
add_index :ec_products, :internal_code, unique: true
```

### `ec_skus` — 主 SKU（master_sku，核心轴心）

```sql
create_table :ec_skus do |t|
  t.references :ec_product, null: false, foreign_key: true
  t.string  :sku_code,     null: false   -- 公司内部 SKU 编码（master_sku）
  t.string  :color
  t.string  :size
  t.string  :barcode                     -- 公司统一条码（EAN/UPC）
  t.string  :status,       default: 'active'  -- active / discontinued
  t.jsonb   :meta,         default: {}
  t.timestamps
end
add_index :ec_skus, :sku_code, unique: true
add_index :ec_skus, :barcode
```

---

## 四、销售数据（4 张表）

### `ec_orders` — 平台订单头（一次购物 / 一张发货单）

```sql
create_table :ec_orders do |t|
  t.string  :platform,          null: false
  t.string  :external_order_id, null: false   -- WB: order_uid; Ozon: posting_number
  t.string  :fulfillment_type                -- 'fbs' / 'fbo'
  t.string  :status,            null: false   -- 标准化状态
  t.string  :raw_status                      -- 平台原始状态
  t.decimal :total_price,       precision: 10, scale: 2
  t.string  :currency,          default: 'RUB'
  t.datetime :ordered_at
  t.datetime :confirmed_at
  t.datetime :delivered_at
  t.datetime :cancelled_at
  t.string  :warehouse_name
  t.string  :region
  t.timestamps
end
add_index :ec_orders, [:platform, :external_order_id], unique: true
add_index :ec_orders, [:platform, :ordered_at]
add_index :ec_orders, [:platform, :status]
```

**标准化 status 枚举：**
`pending` / `confirmed` / `shipped` / `delivered` / `cancelled` / `returned`

**ETL 来源：**
- WB：`raw_wb_orders`（按 order_uid 聚合为订单头）
- Ozon：`raw_ozon_postings_fbs` + `raw_ozon_postings_fbo`（每条 posting = 一张订单）

---

### `ec_order_items` — 订单行（SKU × 数量）

```sql
create_table :ec_order_items do |t|
  t.references :ec_order, null: false, foreign_key: true
  t.references :ec_sku,   null: false, foreign_key: true
  t.string  :platform,    null: false
  t.string  :external_item_id              -- WB: chrt_id（同 order_uid 下）; Ozon: posting_item 行
  t.integer :quantity,    null: false, default: 1
  t.decimal :unit_price,  precision: 10, scale: 2   -- 消费者实付单价
  t.decimal :total_price, precision: 10, scale: 2
  t.string  :currency,    default: 'RUB'
  t.timestamps
end
add_index :ec_order_items, [:ec_order_id, :ec_sku_id]
add_index :ec_order_items, :ec_sku_id
```

**ETL 来源：**
- WB：`raw_wb_orders`（按 order_uid + chrt_id 分组，COUNT = quantity；1 条记录 = 1 件商品）
- Ozon：`raw_ozon_posting_items`（products 数组展开，每行一个 ozon_sku）

---

### `ec_daily_sales` — 每日销售快照（SKU × 平台 × 日）

用于趋势图、对比分析。ETL 每日凌晨跑批。

```sql
create_table :ec_daily_sales do |t|
  t.references :ec_sku,      null: false, foreign_key: true
  t.string  :platform,       null: false
  t.date    :sale_date,      null: false
  t.integer :orders_count,   default: 0    -- 下单件数
  t.integer :buyouts_count,  default: 0    -- 确认买断件数（WB 特有概念）
  t.integer :returns_count,  default: 0    -- 退货件数
  t.integer :cancels_count,  default: 0    -- 取消件数
  t.decimal :gmv,            precision: 12, scale: 2, default: 0   -- 下单金额（含折扣前）
  t.decimal :revenue,        precision: 12, scale: 2, default: 0   -- 实际收入
  t.decimal :returns_amount, precision: 12, scale: 2, default: 0
  t.string  :currency,       default: 'RUB'
  t.timestamps
end
add_index :ec_daily_sales, [:ec_sku_id, :platform, :sale_date], unique: true
add_index :ec_daily_sales, [:platform, :sale_date]
```

**ETL 来源：**
- WB：`raw_wb_stats_sales` + `raw_wb_stats_orders`
- Ozon：`raw_ozon_postings_fbs/fbo`（按日 group by ozon_sku）

---

## 五、库存数据（1 张表）

### `ec_inventory_snapshots` — 库存日快照（SKU × 平台 × 仓库 × 日）

```sql
create_table :ec_inventory_snapshots do |t|
  t.references :ec_sku,         null: false, foreign_key: true
  t.string  :platform,          null: false
  t.date    :snapshot_date,     null: false
  t.string  :warehouse_name,    null: false
  t.string  :fulfillment_type               -- 'fbs' / 'fbo'
  t.integer :qty_available,     default: 0  -- 可销售库存
  t.integer :qty_reserved,      default: 0  -- 已锁定（待发货）
  t.integer :qty_total                      -- 合计
  t.timestamps
end
add_index :ec_inventory_snapshots, [:ec_sku_id, :platform, :snapshot_date, :warehouse_name], unique: true, name: 'idx_ec_inventory_unique'
add_index :ec_inventory_snapshots, [:platform, :snapshot_date]
```

**ETL 来源：**
- WB：`raw_wb_stocks`（warehouse_id + barcode 聚合）
- Ozon：`raw_ozon_product_stocks`（present_fbo/present_fbs + stocks_by_warehouse JSONB 展开）

---

## 六、财务数据（2 张表）

### `ec_monthly_financials` — 月度财务汇总（SKU × 平台 × 月）

```sql
create_table :ec_monthly_financials do |t|
  t.references :ec_sku,          null: false, foreign_key: true
  t.string  :platform,           null: false
  t.integer :year,               null: false
  t.integer :month,              null: false
  t.decimal :gross_revenue,      precision: 12, scale: 2, default: 0  -- 销售额（含折扣）
  t.decimal :returns_deduction,  precision: 12, scale: 2, default: 0  -- 退货扣款
  t.decimal :platform_commission,precision: 12, scale: 2, default: 0  -- 平台佣金
  t.decimal :delivery_fee,       precision: 12, scale: 2, default: 0  -- 平台物流费
  t.decimal :penalty,            precision: 12, scale: 2, default: 0  -- 罚款/扣款
  t.decimal :other_deduction,    precision: 12, scale: 2, default: 0  -- 其他扣除
  t.decimal :net_payout,         precision: 12, scale: 2, default: 0  -- 平台实际打款
  t.integer :orders_count,       default: 0
  t.integer :returns_count,      default: 0
  t.string  :currency,           default: 'RUB'
  t.timestamps
end
add_index :ec_monthly_financials, [:ec_sku_id, :platform, :year, :month], unique: true, name: 'idx_ec_monthly_fin_unique'
```

**ETL 来源：**
- WB：`raw_wb_sales_report_items`（按 nm_id + chrt_id + 月聚合）
  - `gross_revenue` ← `retail_amount`
  - `platform_commission` ← `commission_percent × retail_amount`
  - `delivery_fee` ← `delivery_rub`
  - `net_payout` ← `ppvz_for_pay + additional_payment`
- Ozon：`raw_ozon_finance_realizations`（按 offer_id + 月聚合）
  - `gross_revenue` ← `accruals_for_sale`
  - `net_payout` ← `total_amount`

---

### `ec_finance_transactions` — 财务流水明细

```sql
create_table :ec_finance_transactions do |t|
  t.references :ec_sku,         null: false, foreign_key: true
  t.string  :platform,          null: false
  t.string  :external_id,       null: false    -- 平台侧流水 ID
  t.string  :transaction_type,  null: false    -- sale / return / commission / delivery / penalty / other
  t.string  :operation_type                   -- 平台原始操作类型
  t.decimal :amount,            precision: 10, scale: 2, null: false
  t.string  :currency,          default: 'RUB'
  t.datetime :occurred_at,      null: false
  t.string  :related_order_id               -- 关联订单号
  t.jsonb   :raw_data,          default: {}  -- 平台原始字段备份
  t.timestamps
end
add_index :ec_finance_transactions, [:platform, :external_id], unique: true
add_index :ec_finance_transactions, [:ec_sku_id, :occurred_at]
add_index :ec_finance_transactions, :transaction_type
```

**ETL 来源：**
- WB：`raw_wb_stats_sales`（每笔销售/退货）+ `raw_wb_sales_report_items`（佣金/物流）
- Ozon：`raw_ozon_finance_transactions`（operation_type 映射到 transaction_type）

---

## 七、销售漏斗（1 张表）

### `ec_daily_funnel` — 每日漏斗指标（SKU × 平台 × 日）

```sql
create_table :ec_daily_funnel do |t|
  t.references :ec_sku,          null: false, foreign_key: true
  t.string  :platform,           null: false
  t.date    :funnel_date,        null: false
  t.integer :views,              default: 0   -- 商品页浏览量（PDP views）
  t.integer :add_to_cart,        default: 0   -- 加购数
  t.integer :orders_count,       default: 0   -- 下单数
  t.integer :buyouts_count,      default: 0   -- 购买完成数
  t.decimal :conv_view_to_cart,  precision: 5, scale: 4, default: 0   -- 浏览→加购率
  t.decimal :conv_cart_to_order, precision: 5, scale: 4, default: 0   -- 加购→下单率
  t.decimal :conv_order_to_buy,  precision: 5, scale: 4, default: 0   -- 下单→购买率
  t.decimal :conv_view_to_buy,   precision: 5, scale: 4, default: 0   -- 综合转化率
  t.decimal :avg_order_value,    precision: 10, scale: 2, default: 0  -- 客单价
  t.string  :currency,           default: 'RUB'
  t.timestamps
end
add_index :ec_daily_funnel, [:ec_sku_id, :platform, :funnel_date], unique: true
add_index :ec_daily_funnel, [:platform, :funnel_date]
```

**ETL 来源：**
- WB：`raw_wb_analytics_sales_funnels`（nm_id 映射到 ec_sku_id）
  - `views` ← `open_card`
  - `add_to_cart` ← `add_to_cart`
  - `orders_count` ← `orders`，`buyouts_count` ← `buyouts`
  - `conv_*` ← 公式计算（conv_to_cart / cart_to_order 字段或重算）
- Ozon：`raw_ozon_analytics`（ozon_sku 映射）
  - `views` ← `hits_view_pdp`
  - `add_to_cart` ← `hits_tocart`
  - `orders_count` ← `ordered_units`

---

## 八、成本管理（2 张表）

### `ec_sku_costs` — SKU 成本版本（纯内部，无平台字段）

```sql
create_table :ec_sku_costs do |t|
  t.references :ec_sku,        null: false, foreign_key: true
  t.date    :effective_from,   null: false   -- 该成本版本生效起始日
  t.date    :effective_to                    -- null = 当前有效版本
  t.decimal :purchase_price,   precision: 10, scale: 2, null: false   -- 采购价（含税）
  t.decimal :packaging_cost,   precision: 10, scale: 2, default: 0    -- 包材
  t.decimal :customs_duty,     precision: 10, scale: 2, default: 0    -- 关税（跨境）
  t.decimal :inbound_logistics, precision: 10, scale: 2, default: 0   -- 头程物流
  t.decimal :labeling_cost,    precision: 10, scale: 2, default: 0    -- 贴标/预处理
  t.decimal :other_cost,       precision: 10, scale: 2, default: 0    -- 其他
  t.decimal :total_cogs,       precision: 10, scale: 2, null: false   -- 汇总成本（可计算字段或冗余存储）
  t.string  :currency,         default: 'CNY'   -- 成本计价货币（跨境场景多为人民币）
  t.decimal :exchange_rate,    precision: 8, scale: 4               -- 记账时汇率（→ RUB）
  t.text    :note
  t.timestamps
end
add_index :ec_sku_costs, [:ec_sku_id, :effective_from]
add_index :ec_sku_costs, :ec_sku_id, where: 'effective_to IS NULL', name: 'idx_ec_sku_costs_current'
```

**使用方式：**
- 每次采购/成本变动新建一行，`effective_to` 填上一版本的截止日
- 查当前成本：`WHERE ec_sku_id = ? AND effective_to IS NULL`
- 计算历史毛利：按 `sale_date` 匹配生效期间的成本版本

---

### `ec_cost_details` — 成本明细分项（可选，精细化管理用）

```sql
create_table :ec_cost_details do |t|
  t.references :ec_sku_cost,   null: false, foreign_key: true
  t.string  :cost_type,        null: false   -- purchase / packaging / customs / logistics / labeling / other
  t.string  :description
  t.decimal :amount,           precision: 10, scale: 2, null: false
  t.string  :currency,         default: 'CNY'
  t.string  :supplier                        -- 供应商/服务商名称
  t.string  :invoice_no                      -- 发票号/单据号
  t.timestamps
end
```

---

## 九、ETL 映射速查

> **关联约定**：`ec_skus.sku_code` = `raw_wb_products.vendor_code` = `raw_ozon_products.offer_id`，所有 ETL 通过此字符串直接 JOIN，无需中间映射表。

| ec_* 表 | WB 数据来源 | Ozon 数据来源 | JOIN 键 |
|---------|------------|--------------|---------|
| `ec_orders` | `raw_wb_orders`（按 order_uid 聚合） | `raw_ozon_postings_fbs/fbo` | —（订单头无 sku） |
| `ec_order_items` | `raw_wb_orders`（按 order_uid+chrt_id 分组） | `raw_ozon_posting_items` | vendor_code / offer_id → sku_code |
| `ec_daily_sales` | `raw_wb_stats_sales` | `raw_ozon_postings_*`（group by） | vendor_code / offer_id → sku_code |
| `ec_inventory_snapshots` | `raw_wb_stocks`（via product barcode） | `raw_ozon_product_stocks` | vendor_code / offer_id → sku_code |
| `ec_monthly_financials` | `raw_wb_sales_report_items` | `raw_ozon_finance_realizations` | vendor_code / offer_id → sku_code |
| `ec_finance_transactions` | `raw_wb_stats_sales` | `raw_ozon_finance_transactions` | vendor_code / offer_id → sku_code |
| `ec_daily_funnel` | `raw_wb_analytics_sales_funnels` | `raw_ozon_analytics` | vendor_code / offer_id → sku_code |
| `ec_sku_costs` | — | — | 内部录入，ec_sku_id |

---

## 十、衍生指标（查询层，不建表）

以下指标通过 SQL / 服务层实时计算，不存数据库：

| 指标 | 计算方式 |
|------|---------|
| **毛利率** | `(revenue - total_cogs × quantity) / revenue` |
| **广告 ROI** | `revenue / ad_spend`（需关联 raw_wb_ad_* 或 raw_ozon_promotions） |
| **库销比（DOI）** | `qty_available / avg_daily_sales_30d` |
| **平台佣金率** | `platform_commission / gross_revenue` |
| **跨平台价格差** | 比较不同 platform 的 `unit_price` |
| **退货率** | `returns_count / orders_count` |

---

## 十一、建表顺序

```
1. ec_products
2. ec_skus
3. ec_orders
4. ec_order_items
5. ec_daily_sales
6. ec_inventory_snapshots
7. ec_monthly_financials
8. ec_finance_transactions
9. ec_daily_funnel
10. ec_sku_costs
11. ec_cost_details（可选）
```

---

## 十二、待确认事项

- [ ] `sku_code` 一致性保障：WB vendor_code 和 Ozon offer_id 由人工录入，是否建 lint/校验防止不一致？
- [ ] 成本货币：跨境采购用 CNY，俄境内用 RUB，是否需要多货币支持？
- [ ] 是否需要 `ec_ad_stats` 表聚合广告数据（WB + Ozon 广告）？
- [ ] 财务流水粒度：Ozon 的 `finance_transactions` 是操作级流水，是否需要与 WB 对齐到同一粒度？
