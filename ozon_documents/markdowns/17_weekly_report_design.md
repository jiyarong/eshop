# 周利润报表设计文档

**服务文件**：`app/services/google_sheets/weekly_report_service.rb`  
**输出**：每次运行在 Google Sheet 新建一个 tab，命名格式 `auto-YYYY-WWW`（如 `auto-2026-W18`）

---

## 一、报表结构（30列）

| 列 | 中文表头 | 说明 |
|----|---------|------|
| A | 日期 | 周区间，如 `4.27-5.3`，每组店铺第一行填写 |
| B | 店铺 | 店铺名称，每组第一行填写 |
| C | SKU | 商品 offer_id / 业务编码（如 KJ-228-BK） |
| D | ITEM ID | 平台侧商品 ID（Ozon product_id / WB nm_id） |
| E | 创建日期 | 该 SKU 在平台上架日期（硬编码自模板） |
| F | FBO库存 | 当前 FBO 在库数量 |
| G | 本周定价（白俄） | 本周 BY 售价 |
| H | 上周定价（白俄） | 上周 BY 售价 |
| I | 售价涨跌幅（BY） | `(本周 - 上周) / 上周 × 100%` |
| J | 本周定价（俄罗斯） | 本周 RU 售价 |
| K | 上周定价（俄罗斯） | 上周 RU 售价 |
| L | 售价涨跌幅（RU） | 同 I 列公式 |
| M | 本周销量 | 本周发货单中该 SKU 的总售出件数 |
| N | 上周销量 | 同上，取上一自然周 |
| O | 销量涨跌幅 | `(M - N) / N × 100%` |
| P | 本周销售额 | 本周实际成交金额（RUB） |
| Q | 上周销售额 | 同上 |
| R | 销售额涨跌幅 | `(P - Q) / Q × 100%` |
| S | 本周广告花费 | 本周广告投入（RUB） |
| T | 上周广告花费 | 同上 |
| U | 广告花费涨跌幅 | `(S - T) / T × 100%` |
| V | 本周广告订单 | 本周广告带来的订单数（含分摊） |
| W | 本周广告订单占比 | `V / M × 100%` |
| X | 上周广告订单占比 | 同上，取上周数据 |
| Y | 本周毛利 | **暂为 0**（缺成本数据） |
| Z | 上周毛利 | 同上 |
| AA | 毛利涨跌幅 | 暂为空 |
| AB | 本周毛利率 | 暂为空 |
| AC | 上周毛利率 | 暂为空 |
| AD | 毛利率涨跌幅 | 暂为空 |

---

## 二、店铺与 SKU 定义

报表行结构在代码中硬编码（对应模板 tab 的实际内容），共 4 个店铺 × 若干 SKU = 21 行：

| 店铺 | 平台 | DB account_id | SKU数 | 数据状态 |
|------|------|--------------|-------|---------|
| WB Мировой выбор | WB | 1 | 4 | **全部为 0**（见下文说明） |
| WB2 Taxi | WB | 2 | 3 | **全部为 0** |
| OZON1-NEVASTAL | Ozon | 1 | 5 | **有真实数据** |
| OZON-Domos | Ozon | nil（未入库） | 9 | **全部为 0** |

---

## 三、数据来源与查询逻辑

### 3.1 FBO 库存

**数据表**：`raw_ozon_product_stocks`  
**关键字段**：`offer_id`（关联键）、`present_fbo`（FBO 在库量）  
**查询方式**：

```ruby
RawOzon::ProductStock.all.index_by(&:offer_id)
# 取 stock[offer_id].present_fbo
```

### 3.2 当前售价

**数据表**：`raw_ozon_product_prices`  
**关键字段**：`offer_id`（关联键）、`price`（当前售价，RUB）  
**查询方式**：

```ruby
RawOzon::ProductPrice.all.index_by(&:offer_id)
# 取 price[offer_id].price
```

**已知限制**：数据库只存一个价格字段，无法区分 BY（白俄罗斯）和 RU（俄罗斯）两套定价。目前 BY/RU 两列使用相同的价格，上周价格填 0（历史价格未落库）。

### 3.3 销量与销售额

**数据表**：`raw_ozon_postings_fbs`、`raw_ozon_postings_fbo`  
**关键字段**：

| 字段 | 位置 | 说明 |
|------|------|------|
| `created_at` | 顶层 | 用于过滤周区间 |
| `raw_json -> products[].offer_id` | JSON 数组 | SKU 关联键 |
| `raw_json -> products[].quantity` | JSON 数组 | 本次发货件数 |
| `financial_data -> products[].price` | JSON 数组 | 实际成交价（RUB）；若为 0 则退回 `raw_json.price` |

**查询逻辑**（Ruby 伪代码）：

```
对 PostingFbs + PostingFbo 各自：
  WHERE created_at BETWEEN 周一00:00 AND 周日23:59
  遍历每条 posting 的 raw_json.products 数组：
    取 offer_id, quantity, financial_data 对应 price
    累加到 sales[offer_id].qty / revenue
```

**销售额优先级**：`financial_data.products[price]` > `raw_json.products[price]`

### 3.4 广告花费与广告订单

#### 链路关系（3张表串联）

```
raw_ozon_ad_units                  (全部广告活动)
    ↓ id → ad_unit_id
raw_ozon_ad_unit_products          (活动关联的 Ozon SKU)
    ↓ raw_ozon_product_id
raw_ozon_products                  (商品主数据与 offer_id)
raw_ozon_ad_daily_stats            (每日广告消耗，按 ad_unit_id 聚合)
```

#### 广告活动分类与分摊策略

| 活动类型 | `unit_type` | 归因方式 |
|---------|------------------|---------|
| SKU 广告 | `cpc_campaign` | 通过 `ad_unit_products` 精确关联 offer_id，**按 SKU 数等分** |
| 搜索推广 | `cpo_selected` | 无法关联单个 SKU 时，**按所有 offer_id 等分** |

**关联字段**：

| 字段 | 表 | 说明 |
|------|-----|------|
| `ozon_sku_id` | `raw_ozon_ad_unit_products` | Ozon SKU 级别 ID |
| `raw_ozon_product_id` | `raw_ozon_ad_unit_products` | 关联 `raw_ozon_products.id`，用于取得 offer_id |
| `spend` | `raw_ozon_ad_daily_stats` | 当日广告花费（RUB） |
| `orders_count` | `raw_ozon_ad_daily_stats` | 当日广告带来的订单数 |
| `stat_date` | `raw_ozon_ad_daily_stats` | 用于过滤周区间 |

**查询逻辑**：

```
构建 ad_unit_id → [offer_ids] 映射：
  读取当前 ad_unit_products，通过 raw_ozon_product_id 取得 offer_id

对 AdDailyStat WHERE stat_date IN 周区间，并排除 cost_model=cpo_all_report：
  若 ad_unit 有关联 offer_ids：
    spend_per_sku = stat.spend / offer_ids.count
    每个 offer_id 累加 spend_per_sku
  若 ad_unit 是 cpo_selected：
    spend_per_sku = stat.spend / 所有产品数
    所有 offer_id 均分
```

---

## 四、计算公式

| 指标 | 公式 | 空值处理 |
|------|------|---------|
| 涨跌幅（通用） | `(本周 - 上周) / 上周 × 100%` | 上周为 0 时输出 `""` |
| 广告订单占比 | `广告订单数 / 总销量 × 100%` | 销量为 0 时输出 `""` |
| 毛利 | `销售额 - 成本 - 广告花费 - 平台佣金` | **暂缺成本，输出 0** |
| 毛利率 | `毛利 / 销售额 × 100%` | **暂缺成本，输出 `""`** |

---

## 五、当前数据缺口（已知 TODO）

| 缺口 | 原因 | 影响列 |
|------|------|-------|
| WB 全量为 0 | WB 数据库中的 `article`（如 `fbs-006`）与报表 SKU 编码（如 `KJ-228-BK`）不一致，尚未建立映射 | A~AD 中 WB 部分 |
| OZON-Domos 全量为 0 | 该店铺的 Ozon 账号凭证未录入 DB | A~AD 中 Domos 部分 |
| BY/RU 价格不区分 | `raw_ozon_product_prices` 只存一个 `price` 字段 | G/H/J/K 列 |
| 上周价格为 0 | 历史价格未建表存储（`raw_ozon_product_price_history` 未实现） | H/K 列 |
| 毛利/毛利率为空 | 无成本表（商品 BOM/采购成本），无佣金明细落库 | Y~AD 列 |
| 广告订单归因为近似值 | SKU 广告按关联 SKU 等分；搜索推广按全品等分 | V/W/X 列 |

---

## 六、运行方式

```ruby
# 当前周（自动取上一个完整 Mon-Sun）
GoogleSheets::WeeklyReportService.new.call

# 指定周
GoogleSheets::WeeklyReportService.new(week_start: Date.new(2026, 4, 27)).call
```

输出会在 Google Sheet 中创建新 tab（已存在则清空重写），返回：

```ruby
{ tab: "auto-2026-W18", rows: 21 }
```

---

## 七、数据流向总结

```
Ozon API
  ├── /v3/product/info/stocks     → raw_ozon_product_stocks.present_fbo     → 列F
  ├── /v4/product/info/prices     → raw_ozon_product_prices.price            → 列G/J
  ├── /v2/posting/fbs/list        → raw_ozon_postings_fbs.raw_json           → 列M/P
  ├── /v2/posting/fbo/list        → raw_ozon_postings_fbo.raw_json           → 列M/P
  └── Performance API
        ├── /api/client/campaign               → raw_ozon_ad_units          ┐
        ├── /api/client/campaign/{id}/v2/products → raw_ozon_ad_unit_products ├→ 列S/T/V
        └── /api/client/statistics/daily       → raw_ozon_ad_daily_stats    ┘
```
