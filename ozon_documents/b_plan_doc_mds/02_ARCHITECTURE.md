# Ozon 电商利润分析系统 — 架构文档

> 版本: 1.0  
> 最后更新: 2026-05-13  
> 语言: 中文 / 部分术语保留俄语原文

---

## 目录

1. [系统概述](#1-系统概述)
2. [ASCII 架构图](#2-ascii-架构图)
3. [模块详述](#3-模块详述)
4. [完整数据流](#4-完整数据流)
5. [利润公式](#5-利润公式)
6. [文件组织](#6-文件组织)
7. [关键设计决策](#7-关键设计决策)
8. [已知陷阱与注意事项](#8-已知陷阱与注意事项)

---

## 1. 系统概述

本系统对 **Ozon（俄区电商平台）** 的财务数据进行按 SKU 维度的利润分析。

**核心目标**: 输入 Ozon Seller API 的 `/v1/finance/accrual/by-day` 财务流水 CSV，输出一份 4-Sheet 的 per-SKU 利润 Excel 报告，包含:

- 每 SKU 的收入、各项平台费用、广告费、货物成本、白俄增值税、出口退税、税前/税后净利
- 按目的地（白俄 vs 俄罗斯/出口）拆分
- 广告费分类明细（PPC vs Promotion）
- 汇总报表与未分摊费用

**技术栈**: Python 3, urllib（无第三方 HTTP 库依赖）, openpyxl + pandas（Excel 生成）, ThreadPoolExecutor（并发）

**凭证来源**: `~/.hermes/.env` 文件，环境变量 `OZON_CLIENT_ID` / `OZON_API_KEY`（Seller API）和 `OZON_PERF_CLIENT_ID` / `OZON_PERF_SECRET`（Performance API）

---

## 2. ASCII 架构图

```
┌─────────────────────────────────────────────────────────────┐
│                     Ozon Cloud APIs                         │
│                                                             │
│  ┌──────────────────┐  ┌──────────────────────────────┐    │
│  │  Seller API      │  │  Performance API              │    │
│  │  (api-seller)    │  │  (api-performance)            │    │
│  │                  │  │                               │    │
│  │ /v1/accrual/     │  │ /api/client/token             │    │
│  │   by-day         │  │ /api/client/statistics/json   │    │
│  │   types          │  │ /api/client/statistic/        │    │
│  │   postings       │  │   products/generate           │    │
│  │                  │  │   orders/generate             │    │
│  │ /v2/posting/     │  │ /api/client/statistics/report │    │
│  │   fbo/get        │  └──────────────┬───────────────┘    │
│  │ /v3/posting/     │                 │                     │
│  │   fbs/get        │                 │                     │
│  │ /v3/supply-order/│                 │                     │
│  │   list/get        │                 │                     │
│  │ /v1/supply-order/│                 │                     │
│  │   bundle          │                 │                     │
│  └────────┬─────────┘                 │                     │
└───────────┼───────────────────────────┼─────────────────────┘
            │                           │
            ▼                           ▼
┌───────────────────────────────────────────────────────────────┐
│                    数据采集层                                  │
│                                                               │
│  src/ozon_fetcher_v1.py          src/ad_fetcher.py            │
│  ┌─────────────────────┐        ┌─────────────────────────┐  │
│  │ get_accruals_by_day │        │ _get_perf_token()        │  │
│  │ normalize_accruals  │        │ fetch_ppc_by_campaigns() │  │
│  │   ├ _normalize_item │        │   └ _submit_and_fetch_   │  │
│  │   ├ _normalize_post │        │      json()              │  │
│  │   └ _normalize_non_ │        │ generate_promo_products_  │  │
│  │       item           │        │   report()               │  │
│  │ enrich_with_reversals│        │ parse_promo_products_csv │  │
│  │ fetch_and_save()     │        │ _poll_and_download()     │  │
│  └─────────┬───────────┘        └────────────┬────────────┘  │
│            │                                 │                │
│            ▼                                 ▼                │
│  data/snapshots/ozon/              data/ad_cache/             │
│  realization_v1_YYYY-MM-DD.csv     ppc_json_*.json            │
│                                    promo_products_*.csv       │
└───────────────┬─────────────────────────┬─────────────────────┘
                │                         │
                ▼                         ▼
┌───────────────────────────────────────────────────────────────┐
│                    归属引擎层                                  │
│                                                               │
│  src/attribution.py             src/ad_attribution.py         │
│  ┌──────────────────────┐      ┌──────────────────────────┐  │
│  │ SKUAttribution       │      │ AdAttribution             │  │
│  │ attribute_direct()   │      │ attribute_advertising()   │  │
│  │   ├ 直接归属(ITEM)   │      │   ├ Promotion → per-SKU  │  │
│  │   ├ posting匹配      │      │   └ PPC → per-SKU        │  │
│  │   │  (支付手续费)    │      │ verify_attribution()     │  │
│  │   ├ 越库分摊         │      │ load_byday_ad_data()     │  │
│  │   │  _resolve_cross- │      └──────────────────────────┘  │
│  │   │  dock_bundle()   │                                     │
│  │   └ 计数统计         │                                     │
│  │ attribution_summary()│                                     │
│  └──────────┬───────────┘                                     │
└─────────────┼─────────────────────────────────────────────────┘
              │
              ▼
┌───────────────────────────────────────────────────────────────┐
│                    辅助数据层                                  │
│                                                               │
│  scripts/query_destinations.py                                │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │ 20线程并发查询 FBO/FBS API                                │ │
│  │ posting_number → {city, is_belarus, delivery_schema}      │ │
│  │ 增量更新 data/order_destination_v2.json                    │ │
│  └──────────────────────────────────────────────────────────┘ │
│                                                               │
│  静态数据文件:                                                │
│  data/sku_master_map.json   — SKU→MasterSKU 成本映射+汇率    │
│  data/sku_product_info.json — SKU→商品名称                    │
│  data/ozon_accrual_types.json — type_id→费用类型码表           │
└──────────────────────────────┬────────────────────────────────┘
                               │
                               ▼
┌───────────────────────────────────────────────────────────────┐
│                    报告生成层                                  │
│                                                               │
│  scripts/phase1_report_v5.py                                  │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │  CLI: --byday <csv_path>                                 │ │
│  │                                                           │ │
│  │  _auto_period()          自动检测报告周期                  │ │
│  │  _ensure_ad_attribution() 缺失→自动拉取PPC+Promotion      │ │
│  │  _ensure_destinations()   缺失→自动查询目的地             │ │
│  │                                                           │ │
│  │  逐SKU利润计算:                                           │ │
│  │   账面 → 扣广告 → 货物成本 → 税前 → 白俄税/出口退税 → 税后│ │
│  │                                                           │ │
│  │  输出: 4-Sheet Excel                                      │ │
│  │   Sheet 1: SKU_Report     逐SKU明细                       │ │
│  │   Sheet 2: Report          汇总报表                       │ │
│  │   Sheet 3: 广告费分类        PPC/Promotion拆分            │ │
│  │   Sheet 4: 订单目的国        白俄/出口统计                 │ │
│  └──────────────────────────────────────────────────────────┘ │
│                                                               │
│  scripts/run_ad_attribution.py  独立广告拉取+归属(可单独运行) │
└───────────────────────────────────────────────────────────────┘
```

---

## 3. 模块详述

### 3.1 `src/ozon_fetcher_v1.py` — Seller API v1 数据采集

**职责**: 从 Ozon Seller API 拉取财务流水，归一化为统一 CSV 格式。

**输入**: 日期范围 (YYYY-MM-DD)  
**输出**: `data/snapshots/ozon/realization_v1_YYYY-MM-DD.csv`

**核心函数**:

| 函数 | 说明 |
|------|------|
| `load_accrual_types(force_refresh)` | 加载费用类型码表，缓存到 `data/ozon_accrual_types.json` |
| `get_accruals_by_day(date_str)` | 调 `POST /v1/finance/accrual/by-day` 获取单日原始计费 |
| `normalize_accruals(raw)` | 将三种类别归一化为扁平行 |
| `enrich_with_reversals(normalized)` | 调 `/postings` 反查补全退货冲正的负 seller_price |
| `fetch_and_save(from, to, path)` | 批量拉取 + 归一化 + 反查补全 + 存 CSV |

**三种原始类别处理**:

```
ITEM    → _normalize_item()   — item_fees.fees[], 按SKU展开每种fee一行
POSTING → _normalize_posting() — posting.products[], seller_price + delivery.services + sale_commission
NON_ITEM → _normalize_non_item() — non_item_fee, 无SKU
```

**输出 CSV 列**: `date, type_id, type_name, amount, sku, posting_number, category`

**退货冲正反查**: `/by-day` 可能不返回同一 posting 内的负 seller_price。脚本检测「既有正 SaleRevenue 又有退货费」的混合 posting，调用 `POST /v1/finance/accrual/postings` 补全。

---

### 3.2 `src/attribution.py` — Phase 1 费用归属引擎

**职责**: 将 CSV 财务流水按 SKU 归集各项费用，并统计下单/成交/退货笔数。

**输入**: `/by-day` CSV 行列表（`list[dict]`，来自 `load_rows_from_csv()`）  
**输出**: `dict[str, SKUAttribution]` — 每个 SKU 的完整归集结果

**`SKUAttribution` 数据类字段**:

| 字段 (俄语语义) | 类型 | 说明 |
|---|---|---|
| `sales_revenue` | float | 销售收入 (Выручка), type_id=0 |
| `commission` | float | 平台佣金 (Комиссия), type_id=69 |
| `delivery_charge` | float | 物流费 (Доставка), Logistic/LastMile等 |
| `payment_fee` | float | 支付手续费 (Эквайринг), type_id=1 |
| `dispatch_fee` | float | 出货费 (Отгрузка), Вывоз товара |
| `packing_fee` | float | 打包费 (Упаковка), Подготовка товара |
| `return_delivery` | float | 退货处理费 (Обработка возврата) |
| `return_refund` | float | 退货退款 (Возврат денег) |
| `storage_fee` | float | 临时仓储 (Врем. хранение) |
| `defect_fee` | float | 残次品处理 (Списание брака) |
| `crossdock_fee` | float | 越库费 (Кросс-докинг) |
| `sales_count` | int | 净成交数 |
| `return_count` | int | 退货笔数 |
| `order_count` | int | 客户下单数 |

**归属策略** (`attribute_direct()`)：

```
策略一: 直接归属 (DIRECT_ATTRIBUTABLE)
  — 交易行 item 含 SKU，费用直接加到该 SKU
  — 涵盖: SaleRevenue, SaleCommission, Logistic系列, PackingFee,
          Вывоз товара, 退货处理/逆向物流, 退货退款, 临时仓储

策略二: posting 匹配 (POSTING_MATCH)
  — 支付手续费 (Acquiring) 行不含 SKU，但有 posting_number
  — 通过第一步收集的 posting→SKU 映射进行反向匹配

策略三: 越库分摊 (_attribute_crossdock)
  — CrossDock 行 category=NON_ITEM, posting_number=supply_order_number
  — 调 Seller API v3 解析 supply order 的 bundle 组成
  — 按 bundle 内各 SKU 数量比例分摊

策略四: 暂不归属
  — 广告费 (Оплата за клик, Продвижение) → Phase 2 处理
  — 比例分摊项 (CrossDock 已处理, 加速评价收集) → 未分摊输出
  — API 反查项 (错误超标, 非推荐时段出库) → 跳过
```

**计数逻辑** (三步法)：
```
第一步: 按 posting 累计净 SaleRevenue
  - posting_net_revenue[pn] = sum(正负 SaleRevenue 行)
第二步: 分类
  - net > 0  → sales (成交) + order (下单)
  - net < 0  → return (退货)
  - net == 0 → order + return (同期下单又退货)
第三步: 去重计数
  - sales_count = len(sales_pns[sku])
  - return_count = len(return_pns[sku])
  - order_count = len(order_pns[sku])
```

**越库 API 调用链**:
```
POST /v3/supply-order/list  → order_id (按 order_number 前缀模糊搜索)
POST /v3/supply-order/get   → bundle_id (筛选 is_crossdock=true)
POST /v1/supply-order/bundle → {sku: quantity}
结果缓存到 _CROSSDOCK_CACHE
```

---

### 3.3 `src/ad_fetcher.py` — Performance API 广告数据拉取

**职责**: 从 Ozon Performance API 获取 PPC 和 Promotion 广告费数据。

**凭证**: `OZON_PERF_CLIENT_ID` / `OZON_PERF_SECRET` → Bearer token (带缓存，到期前 60s 刷新)

**核心函数**:

| 函数 | API 端点 | 说明 |
|------|---------|------|
| `fetch_ppc_by_campaigns()` | `POST /statistics/json` | PPC per-SKU 精确支出 |
| `generate_promo_products_report()` | `POST /statistic/products/generate` | SEARCH_PROMO per-SKU 聚合 |
| `generate_promo_orders_report()` | `POST /statistic/orders/generate` | SEARCH_PROMO 订单报告(保留兼容) |
| `_poll_and_download()` | `GET /statistics/{uuid}` + `GET /statistics/report` | 异步报告轮询+下载 |

**PPC 拉取 (`fetch_ppc_by_campaigns`)**:
```
输入: campaign_ids[] (从 /by-day 中 type_id=41 提取),
      date_from, date_to, batch_size=10 (API 硬限制 ≤10 campaign/批)

流程:
  1. 按 batch_size 分批提交 POST /statistics/json
  2. 每批: 提交 → 轮询 → 下载 JSON
  3. 解析: report.rows → per-SKU 原始值
  4. 归一化: 用 report.totals.moneySpent 作总额，rows 作比例
     scale = totals / raw_sum
     sku_map = {sku: v * scale}
  5. 批次间 sleep(2) 避免 429

输出: {ppc_per_sku, ppc_by_campaign, ppc_total}
缓存: data/ad_cache/ppc_json_result.json
```

**Promotion 拉取 (`generate_promo_products_report`)**:
```
输入: date_from, date_to (RFC 3339 格式, MSK时区 +03:00)

流程:
  1. POST /statistic/products/generate → UUID
  2. 轮询 GET /statistics/{uuid} 直到 state=OK
  3. GET /statistics/report?UUID= → CSV 文本

CSV 解析 (parse_promo_products_csv):
  - 跳过 BOM + 标题行
  - 定位列: SKU, Расход (комбо), Расход (оплата за заказ)
  - per-SKU 聚合: combo_cost + cpo_cost = total_cost

输出: list[dict] — {sku, combo_cost, cpo_cost, total_cost, ...}
```

---

### 3.4 `src/ad_attribution.py` — 广告费归属引擎

**职责**: 将拉取到的广告费数据归属到各 SKU。

**输入**:
- `byday_path` — `/by-day` CSV 路径（用于提取 daily 广告总额做校验）
- `promo_products` — `parse_promo_products_csv()` 结果
- `ppc_per_sku` — `fetch_ppc_by_campaigns()` 结果的 `ppc_per_sku` 字段

**输出**: `dict[str, AdAttribution]` — 每个 SKU 的广告费归属

**`AdAttribution` 字段**: `sku, promotion_cost, ppc_cost, total_ad_cost, ppc_by_campaign, promo_orders_count`

**归属策略**:
```
Promotion (type_id=54, SEARCH_PROMO):
  products/generate 报告已是 per-SKU 聚合，100%精确直接映射
  不再使用 campaign_objects（当前快照不可靠）

PPC (type_id=41, PayPerClick):
  /statistics/json 返回 per-SKU 精确数据，直接映射
  若无 PPC 数据 → 跳过（不再使用 campaign_objects 回退）
```

**验证 (`verify_attribution`)**:
```
/by-day Promotion 总额 vs 归属 Promotion 总额
/by-day PPC 总额 vs 归属 PPC 总额
products/generate 报告总额 vs /by-day Promotion 总额

差异 < 1 ₽ 视为通过
```

---

### 3.5 `scripts/query_destinations.py` — 订单目的地查询

**职责**: 并发查询每个订单的配送城市，判定白俄/出口。

**输入**: `/by-day` CSV 路径  
**输出**: `data/order_destination_v2.json`（增量更新）

**API 调用链**:
```
FBO 优先: POST /v2/posting/fbo/get → analytics_data.city
FBS 回退: POST /v3/posting/fbs/get → analytics_data.city / delivery_method.name
```

**白俄判定逻辑**:
```
1. 城市名: city.upper() in BELARUS_CITIES
2. 仓库前缀 (FBO): warehouse_name.split('_')[0] in BELARUS_CITIES
3. 配送方式 (FBS): delivery_method.name 包含白俄城市名
```

**白俄城市集合** (26 城市): МИНСК, ГОМЕЛЬ, БРЕСТ, ВИТЕБСК, ГРОДНО, МОГИЛЕВ, МОГИЛЁВ, БАРАНОВИЧИ, ОШМЯНЫ, НОВОПОЛОЦК, БОРИСОВ, МОЗЫРЬ, РЕЧИЦА, БОБРУЙСК, КРУПКИ, ДЗЕРЖИНСК, ОРША, ЛИДА, СОЛИГОРСК, ПОЛОЦК, ЖЛОБИН, СВЕТЛОГОРСК, ПИНСК, СЛУЦК, МОЛОДЕЧНО, ЖОДИНО, КОБРИН

**并发**: `ThreadPoolExecutor(max_workers=20)`, 每个查询超时 10s

---

### 3.6 `scripts/phase1_report_v5.py` — 主报告生成器

**职责**: 编排全流程，生成最终 4-Sheet Excel 报告。

**CLI 用法**:
```bash
python scripts/phase1_report_v5.py --byday data/snapshots/ozon/realization_v1_2026-05-10.csv
```

**自动化检查**:
```
_auto_period()            — 从 CSV 提取日期范围 → '2026-05-04_2026-05-10'
_ensure_ad_attribution()  — 缓存缺失时自动拉取 PPC + Promotion
_ensure_destinations()    — 缓存覆盖率不足时自动并发查询
```

**逐 SKU 利润计算**:
```
1. 加载: attribution结果 + ad_data + destinations + cost_mapping + exchange_rate
2. 遍历 all_skus (attribution ∪ ad_data):
   a. 取各费用字段（缺失=0）
   b. 查 MasterSKU → 获取货物成本单价 + 进口增值税
   c. 查目的地 → 白俄笔数/收入, 出口笔数/收入
   d. 净成交 = max(order_count - return_count, 0)
   e. 货物成本 = 净成交 × 单价CNY × 有效汇率
   f. 白俄增值税 = 白俄收入 × 20/120 - 白俄单数 × 进口增值税 × 汇率 (≥0)
   g. 出口退税 = 出口单数 × 进口增值税 × 汇率
   h. 税前 = 扣广告后 - 货物成本
   i. 税后 = 税前 - 白俄税 + 出口退税
3. 排序: 按税后净利降序
```

**未分摊费用**: 从原始 CSV 提取无法归属到 SKU 的费用（加速评价、Placements、延迟罚款、未匹配 Acquiring）

**Excel 结构** (4 Sheets):

| Sheet | 名称 | 内容 |
|-------|------|------|
| SKU_Report | SKU利润明细 | 逐SKU: 28列（收入→费用→广告→成本→税务→利润）+ 底部未分摊 |
| Report | 汇总报表 | 收入/费用/广告/成本/税务/利润 汇总 |
| 广告费分类 | Классификация рекламы | 每SKU的 Promotion/PPC 拆分 |
| 订单目的国 | Страна заказа | 每SKU的白俄/出口订单数 |

---

### 3.7 `scripts/run_ad_attribution.py` — 独立广告拉取工具

**职责**: 可独立运行的广告数据拉取 + 归属脚本（不生成完整报告）。

```bash
python scripts/run_ad_attribution.py --byday <csv> [--output <json>]
```

流程: 提取 PPC campaigns → 拉取 PPC → 拉取 Promotion → 归属 → 验证 → 存 JSON

---

## 4. 完整数据流

```
                          ┌─────────────────┐
                          │  Ozon Seller API │
                          │  /by-day (按日)  │
                          └────────┬────────┘
                                   │
                    ┌──────────────▼──────────────┐
                    │  ozon_fetcher_v1.py          │
                    │  fetch_and_save()            │
                    │  逐日: get_accruals_by_day() │
                    │  归一化: normalize_accruals()│
                    │  反查: enrich_with_reversals │
                    └──────────────┬──────────────┘
                                   │
                    ┌──────────────▼──────────────┐
                    │  data/snapshots/ozon/        │
                    │  realization_v1_YYYY-MM-DD   │
                    │  .csv                        │
                    │  列: date, type_id,          │
                    │  type_name, amount, sku,     │
                    │  posting_number, category    │
                    └──────────────┬──────────────┘
                                   │
          ┌────────────────────────┼────────────────────────┐
          │                        │                        │
          ▼                        ▼                        ▼
┌─────────────────┐   ┌─────────────────────┐   ┌──────────────────────┐
│  attribution.py │   │  ad_fetcher.py      │   │ query_destinations.py│
│                 │   │                     │   │                      │
│ attribute_      │   │ fetch_ppc_by_       │   │ 提取 POSTING 类      │
│ direct()        │   │ campaigns()         │   │ posting_number       │
│                 │   │  └ /statistics/json │   │                      │
│ ├ 直接归属      │   │                     │   │ 20线程并发:          │
│ ├ posting匹配   │   │ generate_promo_     │   │  FBO: /v2/posting/   │
│ ├ 越库分摊      │   │ products_report()   │   │       fbo/get        │
│ └ 计数统计      │   │  └ products/generate│   │  FBS: /v3/posting/   │
│                 │   │                     │   │       fbs/get        │
│ SKUAttribution  │   │ parse_promo_        │   │                      │
│ per-SKU dict    │   │ products_csv()      │   │ → is_belarus判定      │
└────────┬────────┘   └──────────┬──────────┘   └──────────┬───────────┘
         │                       │                          │
         │                       ▼                          │
         │            ┌─────────────────────┐               │
         │            │ ad_attribution.py   │               │
         │            │ attribute_          │               │
         │            │ advertising()       │               │
         │            │                     │               │
         │            │ ├ Promotion: per-   │               │
         │            │ │  SKU 直接映射     │               │
         │            │ └ PPC: per-SKU      │               │
         │            │    精确支出         │               │
         │            │                     │               │
         │            │ verify_attribution()│               │
         │            │ AdAttribution dict  │               │
         │            └──────────┬──────────┘               │
         │                       │                          │
         ▼                       ▼                          ▼
┌────────────────────────────────────────────────────────────────┐
│  data/                          data/ad_cache/    data/        │
│  sku_master_map.json            ad_attribution_   order_       │
│  ├ SKU→MasterSKU                {period}.json     destination_ │
│  ├ 货物成本(CNY)                                   v2.json      │
│  ├ 进口增值税                                                 │
│  └ 有效汇率                                                   │
└──────────────────────────────┬─────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│  scripts/phase1_report_v5.py                                    │
│                                                                 │
│  CLI: --byday <csv>                                             │
│                                                                 │
│  逐 SKU 计算:                                                   │
│  账面利润 = 销售收入 + 各项平台费(负值)                          │
│  扣广告后 = 账面利润 - 广告费                                    │
│  净成交 = max(下单数 - 退货数, 0)                                │
│  货物成本 = 净成交 × 单价CNY × 汇率                              │
│  税前毛利 = 扣广告后 - 货物成本                                  │
│  白俄增值税 = 白俄收入÷1.2×20% - 白俄单数×进口增值税×汇率 (≥0)  │
│  出口退税   = 出口单数 × 进口增值税 × 汇率                       │
│  税后净利   = 税前毛利 - 白俄增值税 + 出口退税                   │
│                                                                 │
│  输出: output/reports/xlsx/{period}_Phase1_SKU利润归集_v5.xlsx  │
│  ├ Sheet 1: SKU_Report      — 逐SKU明细 (28列)                 │
│  ├ Sheet 2: Report          — 汇总报表                          │
│  ├ Sheet 3: 广告费分类       — PPC/Promotion拆分               │
│  └ Sheet 4: 订单目的国       — 白俄/出口统计                     │
└─────────────────────────────────────────────────────────────────┘
```

---

## 5. 利润公式

### 5.1 核心公式

所有金额单位: **俄罗斯卢布 (₽)**，除非标注 CNY。

```
(1) 账面利润 (Book Profit)
    = 销售收入 + Σ平台费
    = sales_revenue + commission + delivery_charge + payment_fee
      + dispatch_fee + packing_fee + return_delivery + return_refund
      + storage_fee + defect_fee + crossdock_fee
    注: 所有平台费均为负值（支出），所以实际是 收入 - 支出

(2) 扣广告后 (Book Profit After Ad)
    = 账面利润 - 广告费
    = book_profit - total_ad_cost

(3) 净成交数 (Net Sales)
    = max(客户下单数 - 退货笔数, 0)
    = max(order_count - return_count, 0)
    注: 用 posting 去重计数，非行数

(4) 货物成本 (Goods Cost)
    = 净成交数 × 单价CNY × 有效汇率
    = net_sales × cost_cny × rate_effective
    注: rate_effective = rate_cny_rub × (1 + rate_buffer_pct/100)

(5) 税前毛利 (Pre-Tax Profit)
    = 扣广告后 - 货物成本
    = book_profit_adj - goods_cost
    注: 无成本数据的 SKU 税前 = 扣广告后

(6) 白俄增值税 (Belarus VAT)
    = max(白俄收入 ÷ 1.2 × 20% - 白俄单数 × 进口增值税 × 汇率, 0)
    = max(blr_sale * 20/120 - blr_cnt * import_vat * rate, 0)
    — 输出部分 (20/120): 白俄增值税法规定，售价含税20%，销项=收入÷1.2×20%
    — 抵扣部分: 进口增值税按单抵扣
    — 下限为 0 (不产生退税)

(7) 出口退税 (Export VAT Refund)
    = 出口单数 × 进口增值税 × 汇率
    = rus_cnt × import_vat × rate
    注: 出口至俄联邦以外(包括俄罗斯本土地址但对卖家视为出口)，
        可退进口增值税

(8) 税后净利 (After-Tax Profit)
    = 税前毛利 - 白俄增值税 + 出口退税
    = pre_tax - blr_tax + rus_refund

(9) 税后利润率 (After-Tax Margin)
    = 税后净利 / 销售收入 × 100%
    (仅当销售收入 > 0 时计算)

(10) 税后净利 (含未分摊)
    = 税后净利 + 未分摊费用合计
    注: 未分摊费用为负值，所以实际是进一步扣减
```

### 5.2 特殊处理

```
白俄收入拆分:
  从 SaleRevenue (type_id=0, category=POSTING, amount>0) 中
  按 posting_number 查目的地，白俄的汇总为 blr_sale，其余为 rus_sale

目的地计数:
  只统计 amount>0 的 SaleRevenue posting 数
  白俄笔数 = blr_cnt, 出口笔数 = rus_cnt

净成交 vs 目的地计数:
  净成交 = 下单 - 退货 (跨周期，反映真实成交)
  目的地计数 = 仅正收入 posting (当前周期内)
  两者可能不等（如：跨周期退货、目的地缺失等）
  货物成本使用净成交计算
  税务使用目的地计数计算

未分摊费用:
  - AcceleratedReviewCollection (加速评价收集)
  - Placements (仓储放置)
  - DefectFineShipmentDelayRate (延迟罚款)
  - Acquiring unmatched (支付手续费未匹配到 posting)
  这些费用在 Sheet 1 底部单独列出，并从税后净利中扣减
```

---

## 6. 文件组织

```
ecommerce-analytics/
│
├── src/                            # 核心库
│   ├── __init__.py
│   ├── ozon_fetcher_v1.py          # Seller API v1 数据采集
│   ├── ozon_fetcher.py             # (旧版，v3 API)
│   ├── attribution.py              # Phase 1 费用归属引擎
│   ├── ad_fetcher.py               # Performance API 广告拉取
│   ├── ad_attribution.py           # 广告费归属引擎
│   ├── fetcher.py                  # (通用 fetcher)
│   ├── analyzer.py                 # (分析器)
│   ├── reporter.py                 # (报告器)
│   └── utils.py                    # (工具函数)
│
├── scripts/                        # 可执行脚本
│   ├── phase1_report_v5.py         # ★ 主报告生成器 (v5)
│   ├── run_ad_attribution.py       # 独立广告拉取+归属
│   └── query_destinations.py       # 目的地并发查询
│
├── data/                           # 数据文件
│   ├── sku_master_map.json         # SKU→MasterSKU 成本映射
│   │                               #   version, rate_cny_rub, rate_buffer_pct,
│   │                               #   rate_effective, mapping, costs
│   ├── sku_product_info.json       # SKU→商品名称
│   ├── ozon_accrual_types.json     # type_id→{name, desc} 码表
│   ├── order_destination_v2.json   # posting→{city,is_belarus,schema}
│   ├── order_destination.json      # (旧版目的地缓存)
│   ├── sku_destination_split.json  # (SKU级目的地拆分)
│   ├── sku_to_master.json          # (旧版映射)
│   │
│   ├── snapshots/ozon/             # /by-day CSV 快照
│   │   ├── realization_v1_2026-04-26.csv
│   │   ├── realization_v1_2026-05-03.csv
│   │   ├── realization_v1_2026-05-10.csv
│   │   └── realization_v1_2026-05-12.csv
│   │
│   └── ad_cache/                   # 广告数据缓存
│       ├── ppc_json_result.json    # PPC 最新结果
│       ├── ppc_json_<period>.json  # PPC 按周期
│       ├── promo_products.csv      # Promotion 最新
│       ├── promo_products_w*.csv   # Promotion 按周
│       ├── ad_attribution.json     # 归属结果最新
│       ├── ad_attribution_<period>.json  # 归属按周期
│       ├── verify*.json            # 验证数据
│       ├── campaign_objects.json   # (旧: campaign→SKU映射)
│       ├── promo_orders.csv        # (旧: 订单报告)
│       └── ppc_per_sku*.json       # (旧: PPC per-SKU)
│
├── output/reports/                 # 输出报告
│   ├── xlsx/                       # Excel 报告
│   │   └── <period>_Phase1_SKU利润归集_v5.xlsx
│   └── md/                         # Markdown 报告 (旧)
│
├── docs/                           # 文档
│   ├── ARCHITECTURE.md             # ★ 本文档
│   └── wb-api-reference.md         # Wildberries API 参考 (独立项目)
│
├── wildberries/                    # Wildberries 子项目 (独立)
│   ├── README.md
│   └── docs/                       # WB API 文档 (OpenAPI YAML)
│
└── ~/.hermes/.env                  # 环境变量 (不在项目内)
    OZON_CLIENT_ID=...
    OZON_API_KEY=...
    OZON_PERF_CLIENT_ID=...
    OZON_PERF_SECRET=...
```

---

## 7. 关键设计决策

### 7.1 为什么用 `/v1/finance/accrual/by-day` 替代 `/v3/finance/transaction/list`

- v3 API 返回俄语交易类型名，字段结构与 v1 不同
- v1 API 原生支持三种类别 (ITEM/POSTING/NON_ITEM) 分离，每种有独立的 SKU/费用结构
- v1 返回英文 `type_name`（如 `SaleCommission`），更适合程序化处理
- v1 的 `/postings` 反查机制可以补全退货冲正的负 seller_price

### 7.2 为什么 PPC 用 `/statistics/json` 而不是 `campaign/objects`

- `campaign/objects` 返回的是**当前**活动的 SKU 列表（快照），不是历史实际投放的 SKU
- `/statistics/json` 返回历史实际投放的 SKU + 支出，且 `totals.moneySpent` 与 `/by-day` 完美对应
- `campaign_objects` 仅作回退（当前版本已禁用回退，改为跳过）

### 7.3 为什么 Promotion 用 `products/generate` 而不是 `orders/generate`

- `products/generate` 返回 per-SKU 聚合数据，直接可用
- `orders/generate` 返回订单级数据，需要二次聚合
- 但 `orders/generate` 保留兼容，以防需要订单级明细

### 7.4 为什么 `campaign_objects` 不再用于归属

- **陷阱**: `campaign_objects` 是实时快照。一个 PPC 活动历史上可能投放过 SKU-A，但现在只投 SKU-B
- 如果按当前 `campaign_objects` 归属历史 PPC 费，SKU-A 的支出会丢失
- `/statistics/json` 直接返回历史实际数据，无此问题
- **设计决策**: 优先使用 `/statistics/json`；若缺失则跳过 PPC 归属（不制造错误数据）

### 7.5 净成交 vs 目的地计数的分离

- 净成交用于货物成本计算：`max(下单-退货, 0)`，反映真实去化的商品数量
- 目的地计数用于税务计算：只统计当周期正 SaleRevenue 的 posting，按配送城市拆分白俄/出口
- 两者不强制相等（跨周期退货、目的地缺失均可导致差异）
- **这是正确行为**，不是 bug

### 7.6 越库费 API 解析链

CrossDock 费用行的 `posting_number` 实际是 supply order number，需要通过 3 步 API 调用解析：
```
/v3/supply-order/list  → /v3/supply-order/get → /v1/supply-order/bundle
```
解析结果缓存到 `_CROSSDOCK_CACHE`，避免重复调用。

### 7.7 缓存策略

| 数据 | 缓存位置 | 刷新策略 |
|------|---------|---------|
| 费用类型码表 | `data/ozon_accrual_types.json` | `force_refresh=True` 时刷新 |
| PPC 结果 | `data/ad_cache/ppc_json_result.json` | 每次拉取覆盖 |
| Promotion CSV | `data/ad_cache/promo_products.csv` | 每次拉取覆盖 |
| 广告归属 | `data/ad_cache/ad_attribution_{period}.json` | 按周期缓存，缺失时自动拉取 |
| 目的地 | `data/order_destination_v2.json` | 增量更新，只查询缺失的 posting |
| 越库解析 | 内存 `_CROSSDOCK_CACHE` | 进程内缓存，不持久化 |
| Bearer Token | 内存 `_PERF_TOKEN` | 过期前 60s 自动刷新 |

### 7.8 Excel 列命名约定

- 所有 Excel 列名使用 **中文 + 换行 + 俄语语义翻译**（不保证标准俄语语法，仅语义提示）
- 数字列不带单位后缀
- 费用/成本列以负值输出

---

## 8. 已知陷阱与注意事项

### 8.1 API 限制

| API | 限制 |
|-----|------|
| `/statistics/json` | ≤10 campaign/批，批次间需 sleep(2) 避免 429 |
| `/statistic/products/generate` | 无 campaign 参数，按日期拉所有选定商品 |
| `/postings` 反查 | 批量 ≤50 posting/批 |
| `/v2/posting/fbo/get` | 某些 posting 可能 404 → 自动 fallback FBS |

### 8.2 退货冲正

- `/by-day` 的 POSTING 类中，同一 posting 的退货冲正（负 seller_price）可能不被返回
- `enrich_with_reversals()` 检测「有正 SaleRevenue 又有退货费」的混合 posting
- 调用 `/postings` 反查补全，去重后合并
- **仍然可能遗漏**: 纯退货 posting（无正 SaleRevenue 在同一周期）不会被检测到

### 8.3 白俄判定

- 城市名匹配为主，仓库前缀/配送方式名为辅
- 白俄城市集合硬编码 26 个城市，若 Ozon 新增配送城市可能遗漏
- `warehouse_name` 如 "МИНСК_МПСЦ" 表示仓库在明斯克但配送可能在俄罗斯 → 前缀匹配可能导致误判

### 8.4 越库分摊精度

- 越库费按 bundle 内 SKU 数量比例分摊
- 无法区分各 SKU 的实际体积/重量差异（API 仅返回 quantity）
- 如果 supply order 无法解析（API 失败、非 crossdock），费用丢失

### 8.5 货物成本匹配

- `sku_master_map.json` 维护 SKU→MasterSKU 手动映射
- 新 SKU 未映射 → `cost_cny = None` → 货物成本/税务均为空
- 有效汇率 = `rate_cny_rub × (1 + buffer_pct/100)`，buffered 3%
- 成本数据需手动维护，来自仓库管理系统

### 8.6 未分摊费用

以下费用类型无法归属到 SKU，作为未分摊单独列出:
- `AcceleratedReviewCollection` — 加速评价收集
- `Placements` — 仓储放置
- `DefectFineShipmentDelayRate` — 延迟罚款
- `Acquiring unmatched` — 支付手续费未匹配到 posting（当 Acquiring 的 posting_key 不在 posting_to_skus 中时）

### 8.7 报告周期检测

- `_auto_period()` 取 CSV 中最小/最大日期作为周期
- 不保证日期连续（中间缺失日期不会被检测）
- 周期格式: `YYYY-MM-DD_YYYY-MM-DD` (如 `2026-05-04_2026-05-10`)

### 8.8 环境变量

系统依赖 `~/.hermes/.env` 文件，格式为 `KEY=value`:
```
OZON_CLIENT_ID=12345
OZON_API_KEY=abc...
OZON_PERF_CLIENT_ID=67890
OZON_PERF_SECRET=xyz...
```
缺少任何一个，系统会在对应模块运行时报错退出。

---

## 附录 A: 费用类型速查表

| type_id | English Name | 俄语描述 | 归属方式 |
|---------|-------------|---------|---------|
| 0 | SaleRevenue | Выручка (销售收入) | 直接归属 |
| 1 | Acquiring | Эквайринг (支付手续费) | posting 匹配 |
| 9 | ClientReturn | Обработка возвратов | 直接归属 |
| 12 | CrossDock | Кросс-докинг | 越库分摊 |
| 28 | LastMile | Последняя миля | 直接归属 |
| 29 | LastMileCourier | Доставка курьером | 直接归属 |
| 32 | Drop-Off | Обработка Drop-off | 直接归属 |
| 41 | PayPerClick | Оплата за клик | 广告归属 |
| 45 | PickUpPointReturnAcceptance | Приём возврата в ПВЗ | 直接归属 |
| 54 | SearchPromo | Продвижение в поиске | 广告归属 |
| 59 | ReturnFlowLogistic | Обратная логистика | 直接归属 |
| 60 | PartialReturn | Частичный возврат | 直接归属 |
| 61 | Cancellation | Отмена заказа | 直接归属 |
| 69 | SaleCommission | Комиссия за продажу | 直接归属 |

---

## 附录 B: Excel 输出列清单 (Sheet 1: SKU_Report)

| # | 列名 (中文) | 列名 (俄语) | 公式来源 |
|---|-----------|-----------|---------|
| 1 | SKU | — | Ozon SKU ID |
| 2 | 品号 | Артикул | Master SKU |
| 3 | 商品名称 | Название товара | 截断35字符 |
| 4 | 销售收入 | Выручка | sales_revenue |
| 5 | 平台佣金 | Комиссия Ozon | commission |
| 6 | 物流费 | Доставка | delivery_charge |
| 7 | 支付手续费 | Эквайринг | payment_fee |
| 8 | 出货费 | Отгрузка | dispatch_fee |
| 9 | 打包费 | Упаковка | packing_fee |
| 10 | 退货处理费 | Обработка возврата | return_delivery |
| 11 | 退货退款 | Возврат денег | return_refund |
| 12 | 临时仓储 | Врем. хранение | storage_fee |
| 13 | 残次品处理 | Списание брака | defect_fee |
| 14 | 越库费 | Кросс-докинг | crossdock_fee |
| 15 | 客户下单数 | Заказано | order_count |
| 16 | 净成交数 | Чистые продажи | max(order-return, 0) |
| 17 | 退货笔数 | Возвратов | return_count |
| 18 | 广告费 | Реклама | -total_ad_cost |
| 19 | 广告费占比 | Доля рекламы, % | ad/revenue×100 |
| 20 | 账面利润 | Маржа Ozon | book_profit |
| 21 | 扣广告后 | Маржа после рекламы | book_profit - ad |
| 22 | 白俄 | Заказы в РБ | blr_cnt |
| 23 | 出口 | Заказы на экспорт | rus_cnt |
| 24 | 货物成本 | Себестоимость | -goods_cost |
| 25 | 白俄增值税 | НДС РБ | -blr_tax |
| 26 | 出口退税 | Возмещение НДС (экспорт) | rus_refund |
| 27 | 税前毛利 | Прибыль до налогов | pre_tax |
| 28 | 税后净利 | Чистая прибыль | after_tax |
| 29 | 税后利润率 | Рентабельность, % | after_tax/revenue×100 |

---

> **文档维护**: 本文档随代码演进同步更新。如发现不一致，以源代码为准。
> **相关文档**: `docs/wb-api-reference.md` (Wildberries API 参考，独立子项目)
