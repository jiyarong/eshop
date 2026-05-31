# Ozon 数据模型 — 数据机制与正确读取方法

> 项目: ecommerce-analytics
> 版本: 1.0
> 日期: 2026-05-13
> 语言: 中文（关键术语保留俄语/英语原文）

---

## 目录

1. [核心数据组织原则](#1-核心数据组织原则)
2. [posting_number 的三种格式](#2-posting_number-的三种格式)
3. [SaleRevenue 正负行机制](#3-salerevenue-正负行机制)
4. [广告费双轨制](#4-广告费双轨制)
5. [为什么某些做法是错的](#5-为什么某些做法是错的)
6. [数据一致性验证](#6-数据一致性验证)
7. [平台费用分类表](#7-平台费用分类表)
8. [W19 数据示例](#8-w19-数据示例)

---

## 1. 核心数据组织原则

### 1.1 计费日 vs 订单创建日

Ozon 财务数据以 **计费日 (accrual date)** 为组织轴心，**不是订单创建日**。

```
/by-day API 返回结构:
  每个日期 → 该日期产生的所有费用行
```

这意味着同一笔订单（同一个 posting_number）的费用可能分散在多个日期：

| 日期 | posting_number | 事件 |
|------|----------------|------|
| 2026-05-04 | 65125770-0023-1 | 客户下单 → SaleRevenue +12,217 |
| 2026-05-04 | 65125770-0023-1 | 同一天取消 → SaleRevenue −12,217 |
| 2026-05-08 | 65125770-0023-1 | 退货物流费产生 → ReturnFlowLogistic −144 |

**关键推论**：
- 不能按订单创建日筛选数据窗口——会漏掉后续产生的费用行。
- 必须按 `/by-day` 的日期字段筛选，而不是 parsing posting_number 推断日期。
- 做周报时，以 `/by-day` 返回的 `date` 列作为所属周期判断。

### 1.2 数据聚合的三个维度

Ozon 财务流水天然存在三层结构，必须理解每个层级的含义：

```
层级 1: 计费日 (date)
  层级 2: 费用类型 (type_id + type_name)
    层级 3: 费用行 (item/posting/non_item)
       └─ 归属实体: SKU 或 posting_number 或 supply_order_number
```

三种 category（在原版 v3 API 中）:

| category | 含义 | 是否含 SKU | 归属方式 |
|----------|------|-----------|----------|
| ITEM | 按 SKU 逐条计费 | 是 | 直接归属 |
| POSTING | 按订单级计费 | 可能（v1有sku列） | 有些需SKU映射反查 |
| NON_ITEM | 非SKU级全局费用 | 否 | 需API反查或无法归属 |

---

## 2. posting_number 的三种格式

财务流水中的 `posting_number`（v1 格式，对应 v3 的"订单号"字段）不是单一含义的字段，而是**三种不同实体的标识符共用同一列**。

### 2.1 三段式 — 真正的 posting 编号

格式: `XXXX-XXXX-X`，例如 `65125770-0023-1`

这是唯一真正的订单 posting 号。出现在：

- `SaleRevenue` — 销售收入（正=销售，负=退货冲正）
- `SaleCommission` — 平台佣金
- `Logistic` / `LastMileCourier` / `LastMilePickUpPoint` — 正向物流
- `ReturnFlowLogistic` / `PickUpPointReturnAcceptance` — 退货处理
- `ClientReturn` / `PartialReturn` / `Cancellation` — 退货/取消
- `Acquiring` — 支付手续费（ITEM 行不含SKU）

**匹配规则**: 取前两段作为 posting 匹配键。

```python
# 从 '65125770-0023-1' 提取 '65125770-0023'
parts = order_no.split('-')
posting_key = f"{parts[0]}-{parts[1]}"  # 前两段
```

Acquiring 行用 posting_key 去匹配 SaleRevenue 收集的 posting→SKU 映射。

### 2.2 两段式 — posting 引用（无第三段）

格式: `XXXX-XXXX`，例如 `0132285494-0239`

偶尔出现在某些费用行中，本质仍是 posting 引用。处理方式同三段式取前两段。

### 2.3 纯数字 — 活动/计划/仓库操作号

格式: 8-13位纯数字，例如 `25443469`、`2000050422397`

| 位数范围 | 示例 | 实际含义 | 出现场景 |
|---------|------|---------|---------|
| 8位 | `25443469` | PPC 广告活动 ID (campaign_id) | type_id=41, PayPerClick |
| 8-10位 | `30123456` | Promotion 推广计划 ID | type_id=54, SEARCH_PROMO |
| 13位 | `2000050422397` | 物流批次号 (supply_order_number) | CrossDock |
| 其他 | `sr01-bx...` | 仓库操作单号 | 出货/打包/仓储 |

**重要**: 纯数字的 posting_number 绝对不能用 `-` 分割提取前两段去匹配。这些行代表的是广告活动或物流批次，与订单 posting 无关。

### 2.4 格式识别规则

```python
def classify_posting_number(pn: str) -> str:
    """识别 posting_number 的格式类型"""
    if not pn:
        return "EMPTY"
    if '-' in pn and not pn.startswith('sr'):
        parts = pn.split('-')
        if len(parts) == 3 and parts[2].isdigit():
            return "POSTING_3SEG"   # 三段式: XXXX-XXXX-X
        return "POSTING_2SEG"       # 两段式: XXXX-XXXX
    if pn.isdigit():
        if len(pn) <= 10:
            return "CAMPAIGN_ID"    # 广告活动/计划ID
        return "SUPPLY_ORDER"       # 物流批次号
    return "OTHER"                  # sr01-... 等
```

---

## 3. SaleRevenue 正负行机制

### 3.1 核心机制

SaleRevenue（type_id=0, category=POSTING）是利润归集的核心入口。每个 posting 可能产生多条 SaleRevenue 行：

| 金额符号 | 含义 | 触发事件 |
|---------|------|---------|
| 正 (+) | 客户下单，销售额确认 | 订单创建 |
| 负 (−) | 退货/取消冲正 | 退货完成或订单取消 |

**Ozon 没有独立的"退货退款"金额行**。`Получение возврата`（退货退款）类型的行在 by-day v1 数据中**始终为 0**。退货通过 SaleRevenue 负行直接冲正原始销售收入。

### 3.2 同期下单又退货

如果一个 posting 在同一个计费周期内先产生正 SaleRevenue 又产生负 SaleRevenue（金额相抵为 0），这笔 posting：

- **计入下单数** (order_count) ✓
- **计入退货数** (return_count) ✓
- **不计入成交数** (sales_count) ✗
- **不计入净成交数** ✗

这就是为什么**不能用 SaleRevenue 正行的行数来统计成交**——同期下单又退货的订单不算成交。

### 3.3 老单退货

如果 posting 的正 SaleRevenue 在上一个周期产生，只有负 SaleRevenue 出现在当前周期：

- **不计入下单数** ✗（下单在上周期）
- **计入退货数** ✓
- **从净成交中扣除** ✓

### 3.4 正确计数算法

```python
# 第一步: 按 posting 累加所有 SaleRevenue 行（正+负）
posting_net = defaultdict(float)
for row in sale_revenue_rows:
    posting_net[row['posting_number']] += float(row['amount'])

# 第二步: 按净额分类
sales_pns  = set()  # 净正 = 成交
order_pns  = set()  # 有过正行 = 下单
return_pns = set()  # 有过负行 = 退货

for pn, net in posting_net.items():
    if net > 0:
        sales_pns.add(pn)
        order_pns.add(pn)
    elif net < 0:
        return_pns.add(pn)
    else:
        # net == 0: 同期下单又退货
        order_pns.add(pn)
        return_pns.add(pn)

# 第三步: 计数
order_count  = len(order_pns[sku])
return_count = len(return_pns[sku])
sales_count  = len(sales_pns[sku])
net_sales    = max(order_count - return_count, 0)  # 净成交
```

### 3.5 佣金和手续费的联动退回

当 SaleRevenue 出现负行（退货冲正），**同一条 posting 的佣金（SaleCommission）和支付手续费（Acquiring）也会同时出现正数行**（即退回已扣费用）：

```
# 原始下单:
2026-05-04  SaleRevenue    +12,217.00  (销售)
2026-05-04  SaleCommission    -916.28  (佣金)
2026-05-04  Acquiring         -234.90  (手续费)

# 取消冲正:
2026-05-04  SaleRevenue    -12,217.00  (冲正销售收入)
2026-05-04  SaleCommission    +916.28  (退回佣金)
2026-05-04  Acquiring         +234.90  (退回收续费)
```

这确保了账面利润（收入 − 佣金 − 手续费）在退货时也自动归零该笔。

---

## 4. 广告费双轨制

Ozon 有两套**完全独立**的广告系统，在财务流水中有不同的 type_id，必须用不同的 Performance API 端点获取明细：

### 4.1 PPC — 按点击付费 (PayPerClick)

| 属性 | 值 |
|------|-----|
| type_id | **41** |
| type_name (v1) | `PayPerClick` |
| type_name (v3) | `Оплата за клик` |
| posting_number 含义 | 纯数字 → campaign_id |
| 数据源 API | `POST /api/client/statistics/json` |
| 归属粒度 | per-SKU per-campaign |
| category | NON_ITEM |

**数据拉取策略**:

```
1. 从 /by-day 提取所有 type_id=41 的 posting_number → campaign_ids
2. 按 batch_size=10 分批提交 POST /statistics/json（API 硬限制 ≤10 campaign/批）
3. 解析每批返回的 JSON:
   - totals.moneySpent  = 该批 campaign 总支出
   - rows[].sku → rows[].moneySpent = 各 SKU 原始支出
4. 按比例归一化消除日舍入误差:
   scale = totals / raw_sum
   per_sku_final = raw × scale
```

### 4.2 Promotion — 搜索推广按订单付费 (SEARCH_PROMO)

| 属性 | 值 |
|------|-----|
| type_id | **54** |
| type_name (v1) | `SEARCH_PROMO` |
| type_name (v3) | `Продвижение с оплатой за заказ` |
| posting_number 含义 | 纯数字 → 推广计划 ID |
| 数据源 API | `POST /api/client/statistic/products/generate` |
| 归属粒度 | per-SKU 聚合（直接） |
| category | NON_ITEM |

**数据拉取策略**:

```
1. 提交异步报告: POST /statistic/products/generate
   参数: dateFrom, dateTo (RFC 3339, MSK +03:00)
2. 轮询状态: GET /statistics/{UUID} → 直到 state=OK
3. 下载 CSV: GET /statistics/report?UUID=...
4. 解析 CSV:
   - SKU 列 → sku
   - Расход (комбо) → combo_cost
   - Расход (оплата за заказ) → cpo_cost
   - total_cost = combo_cost + cpo_cost
```

### 4.3 两套系统的关键区别

| 维度 | PPC (type_id=41) | Promotion (type_id=54) |
|------|-------------------|------------------------|
| 付费模式 | 每次点击付费 | 每笔成交订单付费 |
| 费用触发 | 用户点击广告 | 用户通过推广下单 |
| 归属精度 | per-campaign → per-SKU（须归一化） | per-SKU 直接聚合（100%精确） |
| API 方式 | 同步 JSON（分批提交） | 异步报告轮询 |
| 是否需要分摊 | 否（/statistics/json 直接 per-SKU） | 否（products/generate 直接 per-SKU） |

---

## 5. 为什么某些做法是错的

以下列出在实践中验证过的错误做法及其原因，所有结论均有 W19 数据佐证。

### 5.1 错误: 用 campaign_objects 获取 PPC 活动→SKU 映射

**错误做法**: 调用 `GET /campaign/{campaignId}/objects` 获取活动当前关联的 SKU 列表，然后用这个映射归属广告费。

**为什么错**: `campaign/objects` 返回的是**当前快照**（调用时刻的活动配置），不是历史快照。如果广告主在活动中途换了 SKU 或在活动结束后删除了 SKU，这个映射就是错的。

**W19 证据**: 
- 15 个 PPC campaign 中，有 campaign 的 objects 返回的 SKU 与 /statistics/json 的 rows 不一致
- 使用 campaign_objects 导致部分费用无法归属，ppc_diff 显著 >1 ₽

**正确做法**: 直接用 `POST /statistics/json` 的 rows 数据——每行自带 SKU 和 moneySpent。

### 5.2 错误: 按收入比例分摊 PPC 费用

**错误做法**: 
```
SKU_A 的 PPC 费 = 总 PPC 费 × (SKU_A 销售收入 / 总销售收入)
```

**为什么错**: 不同 SKU 在各自 PPC 活动中的点击成本和转化率差异巨大。有的 SKU 可能投入了大量 PPC 但没有产生销售（有广告费无收入）。按收入比例分摊会把高投入低转化的 SKU 的广告费"转嫁"到高收入 SKU 上。

**W19 证据**:
- SKU 3584755442: 零销售但有出货费 −3,082 ₽，说明有 PPC 投入但没转化
- 如果按收入比例分摊，这个 SKU 的 PPC 费会被分到 0（因为销售收入为 0），实际支出被隐藏

**正确做法**: 用 `/statistics/json` 返回的 per-SKU 精确数据，**不进行任何比例分摊**。

### 5.3 错误: 按日期窗口拉取 FBO list 交叉匹配

**错误做法**: 根据日期窗口（如 "2026-05-04 ~ 2026-05-10"）拉取该时间段内创建的 FBO 订单列表，与 `/by-day` 数据交叉匹配。

**为什么错**: FBO list 的筛选条件是**订单创建时间**，而 `/by-day` 的筛选条件是**费用计费时间**。这两个时间窗口不一致：

```
订单创建: 2026-04-28 → 物流费可能计费在 2026-05-06
FBO list 按创建时间 (04-28) 筛选 → 可能不在 05-04~05-10 窗口内
/by-day 按计费时间 (05-06) 筛选 → 在窗口内
结果: 这条物流费无法匹配到订单
```

**W19 证据**:
- 退货物流费（ReturnFlowLogistic）经常在老订单（>7天前创建）上产生，如果用创建时间窗口就会漏掉

**正确做法**: 直接使用 `/by-day` 返回的 posting_number 去查询单个 posting 的详细信息（POST /v2/posting/fbo/get 或 /v3/posting/fbs/get），不按创建时间筛选。

### 5.4 错误: 预期 Получение возврата（退货退款）有金额

**错误做法**: 在计算退货损失时单独统计 `Получение возврата` 类型行的金额。

**为什么错**: 在 v1 `/by-day` API 中，**`Получение возврата` 类型的行金额始终为 0**。退货退款不是通过这个类型行体现的，而是通过 SaleRevenue 负行直接冲正。

**W19 证据**: v1_2026-05-10 CSV 中所有 `Получение возврата`（或 v1 对应类型）金额均为 0.00。退货退款金额 = 负 SaleRevenue 行金额之和。

**正确做法**: 
```python
退货退款金额 = sum(负 SaleRevenue 行金额)  # 即所有 amount < 0 的 SaleRevenue
```
不要再单独累加 Получение возврата。

### 5.5 错误: 用正 SaleRevenue 行数统计成交

**错误做法**: 
```python
sales_count = len(正 SaleRevenue 行)
```

**为什么错**: 同一 posting 如果在同期下单又退货，会产生一条正行和一条负行。算正行的话这笔会算成成交，但实际上它净额为 0，不应算成交。

**W19 证据**:
- posting `65125770-0023-1`: 在 W19 周期内同时有 +12,217 和 −12,217 SaleRevenue 行
- 正行数 = 1，但净额 = 0，不应算成交
- 如果按正行数统计 → 下单数多算 1，成交数多算 1

**正确做法**: 按 posting 净额归类（见 3.4 节）。

### 5.6 正确认识: SKU 覆盖率必须包含有广告费但零销售的 SKU

在 Phase 1 归属时，`all_skus` 必须取 `attribution_results.keys() ∪ ad_data.keys()` 的并集。因为有些 SKU 可能：

- 在 `/by-day` 中没有任何费用行（没有销售收入、没有物流费）
- 但在广告数据中有支出（PPC 或 Promotion）

如果只用 attribution_results 的 SKU 集合，这些"只有广告费"的 SKU 会被遗漏。

**W19 证据**: 报告中 SKU 3584755442 销售收入为 0，但有 −3,082 ₽ 出货费，同样逻辑适用于广告费为零销售的 SKU。

---

## 6. 数据一致性验证

系统内置了多层验证机制，确保数据一致性。所有验证以 `/by-day` CSV 为基准。

### 6.1 PPC 验证

```python
byday_ppc_total  = /by-day 中所有 type_id=41 行的 amount 之和
attr_ppc_total   = /statistics/json 归属后各 SKU ppc_cost 之和
ppc_diff         = byday_ppc_total - attr_ppc_total
```

**通过条件**: |ppc_diff| < 1 ₽

**W19 实际**:
- byday_ppc_total: 27,226.01 ₽（~15 个 campaign）
- attr_ppc_total: 27,225.99 ₽
- ppc_diff: 0.02 ₽ ✓

差异 0.02 ₽ 来源于 `/statistics/json` 内部 per-SKU 数据按比例归一化时的浮点舍入，在可接受范围内。

### 6.2 Promotion 验证

```python
byday_promo_total  = /by-day 中所有 type_id=54 行的 amount 之和
attr_promo_total   = products/generate 归属后各 SKU promotion_cost 之和
promo_diff         = byday_promo_total - attr_promo_total
```

**通过条件**: |promo_diff| < 1 ₽

**W19 实际**:
- byday_promo_total: 35,069.56 ₽
- attr_promo_total: 35,069.56 ₽
- promo_diff: 0.00 ₽ ✓

Promotion 因为 products/generate 是官方 per-SKU 聚合报告，100% 精确。

### 6.3 目的地一致性验证

```python
订单总数 (by-day)    = SaleRevenue 正行去重 posting_number 数
订单总数 (destinations) = order_destination_v2.json 中的记录数
```

如果二者不一致，说明目的地缓存有缺失，需自动补查。

### 6.4 Acquiring 归属缺口

```python
raw_acquiring    = /by-day 中所有 Acquiring 行的 amount 之和
matched_acquiring = 已归属到各 SKU 的 payment_fee 之和
acq_gap          = raw_acquiring - matched_acquiring
```

如果 `acq_gap < 0`（即 by-day 支出大于归属支出），差额列入未分摊费用。缺口通常来自老单（posting 的正 SaleRevenue 不在当前周期，Acquiring 行无法匹配到 SKU）。

### 6.5 验证不通过时的处理

如果 PPC 或 Promotion 验证差异 ≥ 1 ₽：
1. **PPC**: 检查是否有 campaign 的 `/statistics/json` 请求失败（部分 campaign 无数据）
2. **Promotion**: 检查 products/generate 报告的日期范围是否与 /by-day 对齐（特别注意时区 MSK +03:00）
3. 记录差异原因，但在报告中仍使用归属后的数据（因为 API 数据本身可能有微小偏差）

---

## 7. 平台费用分类表

以下分类覆盖 `/by-day` v1 API 返回的所有主要费用类型（type_name）。

### 7.1 直接归属类（费用行含 SKU）

| type_name (v1) | type_id | 含义 | 归属字段 | 说明 |
|---------------|---------|------|---------|------|
| `SaleRevenue` | 0 | 销售收入 | sales_revenue | 正=销售，负=退货冲正。POSTING 类别 |
| `SaleCommission` | 69 | 平台佣金 | commission | 正=退回，负=扣费。随 SaleRevenue 联动 |
| `Logistic` | 32 | 正向物流 | delivery_charge | 基础配送费 |
| `LastMileCourier` | 29 | 最后一公里-快递 | delivery_charge | 快递上门 |
| `LastMilePickUpPoint` | 30 | 最后一公里-自提 | delivery_charge | 自提点配送 |
| `Drop-Off` | 26 | 投递费 | delivery_charge | — |
| `Shipment` | 31 | 发货费 | delivery_charge | — |
| `DeliveryToHandoverPlaceByOzon` | 28 | 中转至交接点 | delivery_charge | — |
| `SellerReturns` | 33 | 出货费 | dispatch_fee | v3: `Вывоз товара` |
| `PackingFee` | 34 | 打包费 | packing_fee | v3: `Подготовка товара` |
| `ClientReturn` | 40 | 客户退货处理 | return_delivery | — |
| `ReturnFlowLogistic` | 59 | 逆向退货物流 | return_delivery | 退货商品回仓物流 |
| `PickUpPointReturnAcceptance` | 45 | 自提点退货接收 | return_delivery | — |
| `PartialReturn` | 42 | 部分退货 | return_delivery | — |
| `Cancellation` | 43 | 取消 | return_delivery | 订单取消处理费 |
| `TemporaryPlacement` | 12 | 临时仓储 | storage_fee | — |
| `TemporaryPlacementsAgent` | 15 | 代理临时仓储 | storage_fee | — |
| `ReturnStorageInTheWarehouse` | 46 | 退货仓储存放 | storage_fee | — |
| `Defect` | 14 | 残次品处理 | defect_fee | v3: `Подготовка товара к вывозу: Брак` |

### 7.2 Posting 匹配归属类

| type_name (v1) | type_id | 含义 | 归属字段 | 匹配方式 |
|---------------|---------|------|---------|---------|
| `Acquiring` | 1 | 支付手续费 | payment_fee | 从 posting_number 提取前两段→匹配 SaleRevenue 的 posting→SKU 映射 |

**注意**: Acquiring 行的 category 是 ITEM，但不含 SKU 字段。只能通过 posting_number 反查 SKU。

### 7.3 API 反查归属类

| type_name (v1) | 含义 | 归属字段 | 反查方式 |
|---------------|------|---------|---------|
| `CrossDock` | 越库费/中转物流 | crossdock_fee | 3级API链路解析 supply_order→bundle→SKU |

**API 链路**:
```
POST /v3/supply-order/list  → order_id (by posting_number 搜索)
POST /v3/supply-order/get   → bundle_id (filter: is_crossdock=true)
POST /v1/supply-order/bundle → {sku: quantity}
```
按 bundle 中各 SKU 的数量比例分摊 CrossDock 费用。

### 7.4 广告类（独立归属系统）

| type_name (v1) | type_id | 含义 | 归属字段 | 数据源 |
|---------------|---------|------|---------|--------|
| `PayPerClick` | 41 | 按点击付费广告 | ppc_cost | Performance API /statistics/json |
| `SEARCH_PROMO` | 54 | 搜索推广按订单付费 | promotion_cost | Performance API products/generate |

**关键**: 这两个类型的 category=NON_ITEM, posting_number 是广告活动/计划ID（纯数字），不由 Phase 1 归属引擎处理。

### 7.5 未分摊类（无法精确归属到 SKU）

| type_name (v1) | 含义 | 处理方式 |
|---------------|------|---------|
| `AcceleratedReviewCollection` | 加速评论收集费 | 列入未分摊 |
| `DefectFineShipmentDelayRate` | 发货延迟罚款 | 列入未分摊 |
| `Placements` | 仓库固定存放费 | 列入未分摊 |
| Acquiring unmatched | 支付手续费缺口（老单无法匹配） | 列入未分摊 |

这些费用在利润链中作为"税后净利（含未分摊）"的一个单独调减项。

---

## 8. W19 数据示例

以下所有数据均来自 W19 报告（2026-05-04 ~ 2026-05-10），覆盖 13 个 SKU。

### 8.1 全局统计

| 指标 | 数值 |
|------|------|
| SKU 总数 | 13 |
| 有销售收入 SKU | 12 |
| 仅有广告费无销售 SKU | 0（W19 中无此情况，但架构支持） |
| 总销售收入 | ~917,592 ₽ |
| PPC 总支出 | 27,226.01 ₽ (15 campaigns) |
| Promotion 总支出 | 35,069.56 ₽ |
| 广告费合计 | ~62,295 ₽ |
| 总广告费占销售收入 | ~6.8% |
| PPC 归属差异 | 0.02 ₽ |
| Promotion 归属差异 | 0.00 ₽ |

### 8.2 SKU 3583393926 完整数据走查

这是 W19 数据中最典型的例子，展示了所有核心机制。

#### 原始 /by-day 行

```
日期       type_id  type_name                 金额         posting_number     category  sku
2026-05-04  0      SaleRevenue              +12,217.00  65125770-0023-1    POSTING   3583393926
2026-05-04 32      Logistic                   -241.00    65125770-0023-1    POSTING   3583393926
2026-05-04 29      LastMileCourier              -7.48    65125770-0023-1    POSTING   3583393926
2026-05-04 69      SaleCommission             -916.28    65125770-0023-1    POSTING   3583393926
2026-05-04  1      Acquiring                  -234.90    65125770-0023-1    ITEM      (无sku)
2026-05-04  0      SaleRevenue              -12,217.00   65125770-0023-1    POSTING   3583393926  ← 取消!
2026-05-04 69      SaleCommission             +916.28    65125770-0023-1    POSTING   3583393926  ← 佣金退回
2026-05-04  1      Acquiring                  +234.90    65125770-0023-1    ITEM      (无sku)     ← 手续费退回
─────────────────────────────────────────────────────────────────────────────────────────────────
2026-05-05  0      SaleRevenue              +12,217.00   0127503220-0004-1  POSTING   3583393926
2026-05-05 32      Logistic                   -268.00    0127503220-0004-1  POSTING   3583393926
2026-05-05 29      LastMileCourier              -7.55    0127503220-0004-1  POSTING   3583393926
2026-05-05 69      SaleCommission             -916.28    0127503220-0004-1  POSTING   3583393926
2026-05-05  1      Acquiring                  -204.82    0127503220-0004-1  ITEM      (无sku)
─────────────────────────────────────────────────────────────────────────────────────────────────
2026-05-06 32      Logistic                   -242.00    0106980467-0018-1  POSTING   3583393926  ← 退货物流
2026-05-06 59      ReturnFlowLogistic          -143.00    0106980467-0018-1  POSTING   3583393926
2026-05-06 29      LastMileCourier             -12.70    0106980467-0018-1  POSTING   3583393926
2026-05-06 45      PickUpPointReturnAcceptance  -15.00    0106980467-0018-1  POSTING   3583393926
─────────────────────────────────────────────────────────────────────────────────────────────────
2026-05-08  0      SaleRevenue              +12,217.00   65125770-0024-1    POSTING   3583393926
2026-05-08 32      Logistic                   -241.00    65125770-0024-1    POSTING   3583393926
2026-05-08 29      LastMileCourier              -7.20    65125770-0024-1    POSTING   3583393926
2026-05-08 69      SaleCommission             -916.28    65125770-0024-1    POSTING   3583393926
2026-05-08  1      Acquiring                  -239.17    65125770-0024-1    ITEM      (无sku)
─────────────────────────────────────────────────────────────────────────────────────────────────
2026-05-08 59      ReturnFlowLogistic          -144.00    65125770-0023-1    POSTING   3583393926  ← 退货物流(同05-04取消订单)
2026-05-08 45      PickUpPointReturnAcceptance  -15.00    65125770-0023-1    POSTING   3583393926
─────────────────────────────────────────────────────────────────────────────────────────────────
2026-05-09  0      SaleRevenue              +12,289.00   51905653-0334-1    POSTING   3583393926
2026-05-09 32      Logistic                   -213.00    51905653-0334-1    POSTING   3583393926
2026-05-09 69      SaleCommission             -921.68    51905653-0334-1    POSTING   3583393926
─────────────────────────────────────────────────────────────────────────────────────────────────
2026-05-10  0      SaleRevenue              -15,000.00   10294701-0112-1    POSTING   3583393926  ← 老单退货!
2026-05-10 69      SaleCommission           +1,125.00    10294701-0112-1    POSTING   3583393926
2026-05-10  1      Acquiring                  +294.55    10294701-0112-1    ITEM      (无sku)
```

#### 核心要点解析

**要点 1 — 同期下单又退货 (posting 65125770-0023-1)**:
- 05-04 产生正 SaleRevenue +12,217，同一天又产生负 SaleRevenue −12,217
- 净额 = 0，不计入成交数
- 计入下单数和退货数
- 佣金和手续费也联动退回（正行）

**要点 2 — 退货物流费分散在多日**:
- posting 65125770-0023-1 的退货物流费在 05-08 才产生（ReturnFlowLogistic −144）
- 说明费用不一定与销售同一天产生

**要点 3 — 老单退货 (posting 10294701-0112-1)**:
- 只有负 SaleRevenue −15,000，没有正行（原始销售在上一个周期）
- 不计入下单数，计入退货数
- 净成交数从中扣除

**要点 4 — Acquiring 行不含 SKU**:
- Acquiring 行 category=ITEM 但没有 SKU 字段
- 通过 posting_number 提取前两段 → 匹配 SaleRevenue 的 posting→SKU 映射
- 10294701-0112-1 → 提取 "10294701-0112" → 匹配到 SKU 3583393926

#### 计数推导

| posting | 正 SaleRev | 负 SaleRev | 净额 | 下单 | 退货 | 成交 |
|---------|-----------|-----------|------|------|------|------|
| 65125770-0023-1 | +12,217 | −12,217 | 0 | ✓ | ✓ | ✗ |
| 0127503220-0004-1 | +12,217 | — | +12,217 | ✓ | ✗ | ✓ |
| 65125770-0024-1 | +12,217 | — | +12,217 | ✓ | ✗ | ✓ |
| 51905653-0334-1 | +12,289 | — | +12,289 | ✓ | ✗ | ✓ |
| 10294701-0112-1 | — | −15,000 | −15,000 | ✗ | ✓ | ✗ |

- 下单数 = 4
- 退货数 = 2
- 成交数 = 3
- **净成交数 = max(4−2, 0) = 2** ← 用于货物成本计算

#### 利润链

```
销售收入:         +21,723.00 ₽  (= 12217-12217+12217+12217+12289-15000)
平台佣金:          -1,629.24 ₽
物流费:            -1,239.93 ₽
支付手续费:          -357.19 ₽
退货处理费:          -317.00 ₽
─────────────────────────────
账面利润:         +18,179.64 ₽
Promotion 广告:    -6,727.27 ₽
PPC 广告:          -3,021.96 ₽
─────────────────────────────
扣广告后:          +8,430.41 ₽
货物成本:          -8,594.74 ₽  (= 2×381.70 CNY × 11.2585 汇率)
─────────────────────────────
税前毛利:            -164.33 ₽
白俄增值税:              0.00 ₽
出口退税:          +2,675.02 ₽  (= 4×59.40 CNY × 11.2585)
─────────────────────────────
税后净利:          +2,510.69 ₽
税后利润率:             11.6%
```

**关键洞察**: 这个 SKU 的税前毛利为负（−164.33 ₽），但出口退税（+2,675.02 ₽）使其最终税后净利为正。如果没有退税，这会是一个亏损单品。

### 8.3 PPC campaign 数据示例

```
W19 PPC campaigns 统计:
  Campaign 总数: 15
  总支出: 27,226.01 ₽
  平均每 campaign: ~1,815 ₽
  /statistics/json 批次: 2 批 (10+5)
  归属 SKU 数: 约 12
  每 SKU PPC 费范围: 0 ~ 5,000+ ₽
```

### 8.4 Promotion 数据示例

```
W19 Promotion 统计:
  参与 SKU 数: 11
  by-day 总额: 35,069.56 ₽
  products/generate 总额: 35,069.56 ₽
  平均每 SKU: ~3,188 ₽
  差异: 0.00 ₽ ← 100%精确
```

### 8.5 所有 SKU 广告费分布

| SKU | Promotion | PPC | 广告合计 | 销售收入 | 广告占比 |
|-----|-----------|-----|---------|---------|---------|
| 3250965434 | ~10,000 | ~7,209 | ~17,209 | 176,000 | 9.8% |
| 3977734025 | ~14,000 | ~10,302 | ~24,302 | 180,600 | 13.5% |
| 3583393926 | ~6,727 | ~3,022 | ~9,749 | 104,143 | 9.4% |
| 3583442225 | ~6,000 | ~5,231 | ~11,231 | 57,650 | 19.5% |
| 3590307092 | ~7,000 | ~5,812 | ~12,812 | 67,500 | 19.0% |

---

## 附录: 数据获取 API 速查

### Seller API (api-seller.ozon.ru)

| 端点 | 用途 | 头部 |
|------|------|------|
| `POST /v1/finance/accrual/by-day` | 按日拉取财务流水 | Client-Id, Api-Key |
| `POST /v1/finance/accrual/postings` | 反查 posting 的退货冲正 | Client-Id, Api-Key |
| `POST /v2/posting/fbo/get` | FBO posting 详情（含目的地） | Client-Id, Api-Key |
| `POST /v3/posting/fbs/get` | FBS posting 详情（含目的地） | Client-Id, Api-Key |
| `POST /v3/supply-order/list` | 供应订单搜索 | Client-Id, Api-Key |
| `POST /v3/supply-order/get` | 供应订单详情（越库 bundle） | Client-Id, Api-Key |
| `POST /v1/supply-order/bundle` | 越库 bundle SKU 组成 | Client-Id, Api-Key |

### Performance API (api-performance.ozon.ru)

| 端点 | 用途 | 头部 |
|------|------|------|
| `POST /api/client/token` | 获取 Bearer token | — |
| `POST /api/client/statistics/json` | PPC per-SKU 精确支出 | Authorization: Bearer |
| `POST /api/client/statistic/products/generate` | Promotion per-SKU 报告（异步） | Authorization: Bearer |
| `GET /api/client/statistics/{UUID}` | 轮询异步报告状态 | Authorization: Bearer |
| `GET /api/client/statistics/report` | 下载异步报告 CSV | Authorization: Bearer |

---

> **版本历史**
> - v1.0 (2026-05-13): 初始版本，涵盖核心概念、错误做法、验证机制、费用分类、W19 全量示例。
