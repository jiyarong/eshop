# 电商分析系统 — 业务逻辑手册

> 项目: ecommerce-analytics  
> 数据源: Ozon Seller API v1 (by-day realization)  
> 更新日期: 2026-05-13  
> 版本: v5 (Phase 1 利润归集)

---

## 一、系统概述

本系统将 Ozon 平台的财务交易流水（realization by-day CSV）按 SKU 逐笔归集，计算从"账面利润"到"税后净利"的完整利润链。

### 核心数据流

```
Ozon Seller API v1
  → /v3/finance/realization (by-day CSV)
    → Phase 1: 费用归集 (attribution.py)
    → Phase 2: 广告费归属 (ad_attribution.py)
    → Phase 3: 货物成本/税务/利润链 (phase1_report_v5.py)
      → Excel 四表输出
```

### 输出 Excel 结构

| Sheet | 名称 | 内容 |
|-------|------|------|
| SKU_Report | SKU利润归集 | 逐SKU完整利润链 + 未分摊费用汇总 |
| Report | 汇总报告 | 全局收入/费用/利润汇总 |
| 广告费分类 | Классификация рекламы | 按SKU的Promotion+PPC明细 |
| 订单目的国 | Страна заказа | 按SKU的白俄/出口订单分布 |

---

## 二、费用归集规则

### 2.1 交易类型前缀匹配

所有费用按 `type_name` 前缀匹配分类。兼容 v3（俄文）和 v1（英文）API 格式。

#### 🟢 直接归属类（item 含 SKU，费用直接加到该 SKU）

| 前缀 | v3名称 | v1名称 | 所属字段 |
|------|--------|--------|----------|
| `Доставка покупателю` | 销售配送 | — | sales_revenue, commission, delivery_charge |
| `SaleRevenue` | — | 销售收入 | sales_revenue |
| `SaleCommission` | — | 平台佣金 | commission |
| `Logistic` | — | 正向物流 | delivery_charge |
| `LastMileCourier` | — | 最后一公里 | delivery_charge |
| `LastMilePickUpPoint` | — | 自提点最后一公里 | delivery_charge |
| `Drop-Off` | — | 投递费 | delivery_charge |
| `Shipment` | — | 发货费 | delivery_charge |
| `DeliveryToHandoverPlaceByOzon` | — | 中转费 | delivery_charge |
| `Вывоз товара` | 出货费 | SellerReturns | dispatch_fee |
| `Подготовка товара` | 打包费 | PackingFee | packing_fee |
| `Доставка и обработка возврата` | 退货处理费 | — | return_delivery |
| `Обработка возвратов` | 退货处理 | — | return_delivery |
| `Обратная логистика` | 逆向物流 | ReturnFlowLogistic | return_delivery |
| `ClientReturn` | — | 客户退货 | return_delivery |
| `PickUpPointReturnAcceptance` | — | 自提点退货接收 | return_delivery |
| `PartialReturn` | — | 部分退货 | return_delivery |
| `Cancellation` | — | 取消 | return_delivery |
| `Получение возврата` | 退货退款 | — | return_refund |
| `Временное размещение` | 临时仓储 | TemporaryPlacement, TemporaryPlacementsAgent, ReturnStorageInTheWarehouse | storage_fee |
| `Подготовка товара к вывозу: Брак` | 残次品 | — | defect_fee |

#### 🟡 按 posting 匹配归属类

| 前缀 | v3名称 | v1名称 | 所属字段 |
|------|--------|--------|----------|
| `Оплата эквайринга` | 支付手续费 | Acquiring | payment_fee |

匹配逻辑：从 order_number 提取前两段（如 `0132285494-0239` 来自 `0132285494-0239-1`），与 SaleRevenue 行的 posting 集合进行关联。

**注意**：仅当 `posting_key` 命中本周期的 SaleRevenue 时才能匹配。老单的 Acquiring 行将进入"未分摊"。

#### ⚫ 按 API 反查归属类（CrossDock）

| 前缀 | 所属字段 |
|------|----------|
| `Кросс-докинг` | crossdock_fee |

通过 Ozon Seller API 三级链路解析：
1. `POST /v3/supply-order/list` → 用 order_number 搜索获取 `order_id`
2. `POST /v3/supply-order/get`  → 获取 `bundle_id`（is_crossdock=true 时）
3. `POST /v1/supply-order/bundle` → 获取 `{sku: quantity}` 组成

按 bundle 中各 SKU 的数量比例分摊 CrossDock 费用。

#### 🔴 广告类（Phase 2 处理）

| 前缀 | 说明 |
|------|------|
| `Оплата за клик` | PPC 点击付费 (type_id=41) |
| `Продвижение с оплатой за заказ` | Promotion 订单付费 (type_id=54) |

---

### 2.2 SaleRevenue 正负行含义与计数逻辑

SaleRevenue 行是利润归集的核心入口。

#### 正负含义

| 金额符号 | 含义 |
|----------|------|
| 正 (+) | 客户下单/销售额确认。金额＝商品售价 |
| 负 (−) | 退货/取消冲正。金额＝−原售价 |

#### 计数三指标

```
下单数 (order_count)  = 至少出现一条正 SaleRevenue 的 posting 去重数
退货数 (return_count) = 至少出现一条负 SaleRevenue 的 posting 去重数
成交数 (sales_count)  = 净收入 > 0 的 posting 去重数
净成交数              = max(下单数 − 退货数, 0)    ← 用于货物成本计算
```

#### 关键规则

1. **同一 posting 正负相抵不算成交**：如果一条 posting 在本周期内同时有正负 SaleRevenue 行（如当周下单又取消），净收入为 0，则该 posting 计入 `下单数` 和 `退货数`，但不计入 `成交数(sales_count)`，也不计入 `净成交数`。

2. **老单退货**：只有负 SaleRevenue 行、没有正行的 posting（退货来源于更早周期），仅计入 `退货数`，从净成交中扣除。

3. **部分退货**：同一 posting 有多条负行（金额累加），仍按净收入正负判定。

#### 计数算法实现

```
第一步：遍历所有 SaleRevenue 行
  对每个 posting_number，累加正负金额 → posting_net_revenue[pn]

第二步：按净收入判定
  net > 0  → sales_pns[sku].add(pn), order_pns[sku].add(pn)
  net < 0  → return_pns[sku].add(pn)
  net == 0 → order_pns[sku].add(pn), return_pns[sku].add(pn)

第三步：汇总
  order_count  = len(order_pns[sku])
  return_count = len(return_pns[sku])
  sales_count  = len(sales_pns[sku])
```

---

## 三、广告费归属（Phase 2）

### 3.1 PPC（点击付费）

**数据源**：POST `/api/client/statistics/json`

**归属策略**：
1. 按 campaign 批次提交（每批 ≤10 个，API 硬限制）
2. 对每个 campaign，取 `totals.moneySpent` 作为该 campaign 的总支出（与 by-day CSV 完美对齐）
3. 解析 `rows[].moneySpent` 按 SKU 聚合原始支出
4. **按比例归一化**：`per_sku_cost = raw_sku_sum × (totals / raw_sum)` — 消除日舍入误差

**W19 示例**：
- 15 个 PPC campaign
- by-day 总额：27,226.01 ₽
- 归属总额：27,225.99 ₽
- 差异：0.02 ₽（舍入误差）

### 3.2 Promotion（搜索推广）

**数据源**：POST `/api/client/statistic/products/generate`（异步报告）

**归属策略**：
- 报告直接 per-SKU 聚合（无需手动从订单累加）
- 字段：Комбо-модель 支出 + Оплата за заказ (CPO) 支出 → total_cost
- 100% 精确归属，无比例分摊

**W19 示例**：
- 11 个 SKU 参与了 Promotion
- by-day 总额：35,069.56 ₽
- products/generate 总额：35,069.56 ₽
- 差异：0.00 ₽

### 3.3 验证机制

```python
verify = {
    "byday_promo_total": by-day type_id=54 总额,
    "attr_promo_total": products/generate 归属总额,
    "byday_ppc_total": by-day type_id=41 总额,
    "attr_ppc_total": /statistics/json 归属总额,
    "ppc_diff": byday_ppc_total - attr_ppc_total,
    "promo_diff": byday_promo_total - attr_promo_total,
}
# 通过条件: |ppc_diff| < 1 AND |promo_diff| < 1
```

---

## 四、货物成本

### 4.1 映射链

```
Ozon SKU → sku_master_map.json → Master SKU (品号) → 成本表
```

**SKU → Master SKU 路径**：
1. 优先从 `sku_master_map.json` 直接匹配（通过 offer_id 预建立）
2. 缺失时调用 `POST /v3/product/info/list` 获取 offer_id 后匹配

**Master SKU → 成本字段**（来自 `wb_master_sku_costs.csv`）：
- `purchase_qty`：采购量
- `domestic_price`：国内采购单价 (CNY)
- `shipping`：运费 (CNY)
- `customs`：报关费 (CNY)
- `duty`：关税 (CNY)
- `import_vat`：进口增值税 (CNY)
- `total_cost_cny`：综合成本单价 (CNY) = 以上各项加权均摊

### 4.2 成本计算公式

```
货物成本(RUB) = 净成交数 × total_cost_cny(CNY) × 汇率(rate_effective)
```

**汇率**：
- 基准：`rate_cny_rub`（如 10.9306）
- 缓冲：`rate_buffer_pct`（如 3.0%）
- 有效汇率：`rate_effective = rate_cny_rub × (1 + rate_buffer_pct / 100)`
- W19 有效汇率：11.2585

**净成交数** = `max(下单数 − 退货数, 0)`（见 2.2 节）

### 4.3 W19 SKU 3583393926 示例

| 参数 | 值 |
|------|-----|
| Master SKU | KJ-217-GD |
| 商品名 | Полотенцесушитель с полкой (золото) |
| total_cost_cny | 381.70 CNY |
| rate_effective | 11.2585 |
| 单件 RUB 成本 | 381.70 × 11.2585 = 4,297.37 ₽ |
| 净成交数 | 2（4下单 − 2退货） |
| **货物成本** | **2 × 4,297.37 = 8,594.74 ₽** |

---

## 五、税务计算

### 5.1 白俄增值税（НДС РБ）

仅适用于目的地为白俄罗斯的订单。

```
白俄销项税 = 白俄销售收入 ÷ 1.20 × 20%
白俄进项税 = 白俄订单数 × import_vat(CNY) × rate_effective
白俄应缴税 = max(白俄销项税 − 白俄进项税, 0)
```

**公式说明**：
- 白俄税率 20%，价内税（收入含税，÷1.20 还原不含税基数）
- 进口增值税（import_vat）为进项抵扣
- 若进项 ≥ 销项，应缴税为 0（无退税）

### 5.2 出口退税（Возмещение НДС）

仅适用于目的地为俄罗斯（非白俄）的订单。

```
出口退税额 = 出口订单数 × import_vat(CNY) × rate_effective
```

**公式说明**：
- 对俄出口适用 0% 增值税率，进口环节增值税可退
- 按实际已出口的订单数计算（累计全部正 SaleRevenue 的 posting 去重）

### 5.3 目的地判定

通过 Ozon Seller API `POST /v3/posting/fbs/get` 获取每个 posting 的 `delivery_method.data.warehouse` 字段，判断 `is_belarus` 标志。

**W19 SKU 3583393926 示例**（全部为俄罗斯出口）：

| posting | 目的地 |
|---------|--------|
| 65125770-0023-1 | Казань (Россия) |
| 0127503220-0004-1 | Россия |
| 65125770-0024-1 | Казань (Россия) |
| 51905653-0334-1 | Оренбург (Россия) |

- 白俄订单数：0
- 出口订单数：4
- 白俄应缴税：0
- 出口退税额：4 × 59.40 × 11.2585 = **2,675.02 ₽**

---

## 六、未分摊费用

以下费用类型因无法精确归属到 SKU，列为未分摊项：

| 类型 | 说明 |
|------|------|
| AcceleratedReviewCollection | 加速评论收集费 |
| DefectFineShipmentDelayRate | 发货延迟罚款 |
| Placements | 仓库固定存放费 |
| Acquiring unmatched | 支付手续费中无法匹配 posting 的缺口 |

**Acquiring缺口计算**：
```
acq_gap = by-day Acquiring总额 − 已归属 Acquiring 总额
```
仅当 `acq_gap < 0`（即 by-day 支出大于归属支出）时列入未分摊。

**未分摊费用在利润链中的位置**：在"税后净利"之后单独列示 → **税后净利（含未分摊）**。

---

## 七、完整利润公式链

```
                                                           示例 (W19 SKU 3583393926)
                                                           ──────────────────────────
① 销售收入 (Revenue)
   = Σ SaleRevenue 正负行金额                                 = 21,723.00 ₽
   (4正: 12217+12217+12217+12289)
   (2负: -12217-15000)

② 账面利润 (Book Profit)
   = 销售收入 + 平台佣金 + 物流费 + 支付手续费                 = 21,723.00
     + 出货费 + 打包费 + 退货处理费 + 退货退款                  - 1,629.24  (佣金)
     + 临时仓储 + 残次品处理 + 越库费                           - 1,239.93  (物流)
                                                              - 357.19   (支付)
                                                              - 317.00   (退货处理)
                                                           = 18,179.64 ₽

③ 扣广告后 (Book Profit − Ad Cost)
   = ② − (Promotion + PPC)                                  = 18,179.64
                                                              - 6,727.27  (Promotion)
                                                              - 3,021.96  (PPC)
                                                           = 8,430.41 ₽

④ 减货物成本 (Pre-Tax Profit)
   = ③ − 净成交数 × 成本单价 × 汇率                           = 8,430.41
                                                              - 2 × 381.70 × 11.2585
                                                              - 8,594.74
                                                           = -164.33 ₽

⑤ 减白俄增值税 + 出口退税 (After-Tax Profit)
   = ④ − 白俄应缴税 + 出口退税额                             = -164.33
                                                              - 0          (白俄)
                                                              + 2,675.02   (出口退税)
                                                           = 2,510.69 ₽

⑥ 税后利润率
   = ⑤ ÷ ① × 100%                                          = 2,510.69 ÷ 21,723 × 100%
                                                           = 11.6%

⑦ 税后净利（含未分摊）
   = ⑤ + 未分摊费用合计                                     （取决于全局未分摊分摊方式）
```

### 符号约定

| 字段 | Excel 显示 | 代码内部 |
|------|-----------|----------|
| 收入类 | 正数 | 正数 |
| 费用类 | 负数 | 负数（累加） |
| 佣金/物流/支付等费用 | 负数 | 负数 |
| 货物成本 | 负数 | 正数（goods_cost），Excel 显示取负 |
| 广告费 | 负数 | 正数（total_ad_cost），Excel 显示取负 |
| 白俄增值税 | 负数 | 正数（blr_tax），Excel 显示取负 |
| 出口退税 | 正数 | 正数 |

---

## 八、W19 SKU 3583393926 完整计算过程

### 原始数据（by-day CSV 摘录）

```
日期       type_id  type_name                    金额         posting_number     category
2026-05-04  0      SaleRevenue                 +12,217.00  65125770-0023-1    POSTING
2026-05-04 32      Logistic                     -241.00    65125770-0023-1    POSTING
2026-05-04 29      LastMileCourier                -7.48    65125770-0023-1    POSTING
2026-05-04 69      SaleCommission               -916.28    65125770-0023-1    POSTING
2026-05-04  1      Acquiring                    -234.90    65125770-0023-1    ITEM
2026-05-04  0      SaleRevenue                -12,217.00   65125770-0023-1    POSTING  ← 取消
2026-05-04 69      SaleCommission               +916.28    65125770-0023-1    POSTING  ← 佣金退回
2026-05-04  1      Acquiring                    +234.90    65125770-0023-1    ITEM     ← 手续费退回
───────────────────────────────────────────────────────────────────────────────────────
2026-05-05  0      SaleRevenue                +12,217.00   0127503220-0004-1  POSTING
2026-05-05 32      Logistic                     -268.00    0127503220-0004-1  POSTING
2026-05-05 29      LastMileCourier                -7.55    0127503220-0004-1  POSTING
2026-05-05 69      SaleCommission               -916.28    0127503220-0004-1  POSTING
2026-05-05  1      Acquiring                    -204.82    0127503220-0004-1  ITEM
───────────────────────────────────────────────────────────────────────────────────────
2026-05-06 32      Logistic                     -242.00    0106980467-0018-1  POSTING  ← 退货物流
2026-05-06 59      ReturnFlowLogistic            -143.00    0106980467-0018-1  POSTING
2026-05-06 29      LastMileCourier               -12.70    0106980467-0018-1  POSTING
2026-05-06 45      PickUpPointReturnAcceptance    -15.00    0106980467-0018-1  POSTING
───────────────────────────────────────────────────────────────────────────────────────
2026-05-08  0      SaleRevenue                +12,217.00   65125770-0024-1    POSTING
2026-05-08 32      Logistic                     -241.00    65125770-0024-1    POSTING
2026-05-08 29      LastMileCourier                -7.20    65125770-0024-1    POSTING
2026-05-08 69      SaleCommission               -916.28    65125770-0024-1    POSTING
2026-05-08  1      Acquiring                    -239.17    65125770-0024-1    ITEM
───────────────────────────────────────────────────────────────────────────────────────
2026-05-08 59      ReturnFlowLogistic            -144.00    65125770-0023-1    POSTING  ← 退货物流
2026-05-08 45      PickUpPointReturnAcceptance    -15.00    65125770-0023-1    POSTING
───────────────────────────────────────────────────────────────────────────────────────
2026-05-09  0      SaleRevenue                +12,289.00   51905653-0334-1    POSTING
2026-05-09 32      Logistic                     -213.00    51905653-0334-1    POSTING
2026-05-09 69      SaleCommission               -921.68    51905653-0334-1    POSTING
───────────────────────────────────────────────────────────────────────────────────────
2026-05-10  0      SaleRevenue                -15,000.00   10294701-0112-1    POSTING  ← 老单退货
2026-05-10 69      SaleCommission             +1,125.00    10294701-0112-1    POSTING
2026-05-10  1      Acquiring                    +294.55    10294701-0112-1    ITEM
```

### 计数推导

| posting | 正 SaleRevenue | 负 SaleRevenue | 净收入 | 归类 |
|---------|---------------|---------------|--------|------|
| 65125770-0023 | +12,217 | −12,217 | 0 | 下单✓ 退货✓ 成交✗ |
| 0127503220-0004 | +12,217 | — | +12,217 | 下单✓ 退货✗ 成交✓ |
| 65125770-0024 | +12,217 | — | +12,217 | 下单✓ 退货✗ 成交✓ |
| 51905653-0334 | +12,289 | — | +12,289 | 下单✓ 退货✗ 成交✓ |
| 10294701-0112 | — | −15,000 | −15,000 | 下单✗ 退货✓ 成交✗ |

- 下单数 = 4（65125770-0023, 0127503220-0004, 65125770-0024, 51905653-0334）
- 退货数 = 2（65125770-0023, 10294701-0112）
- 净成交数 = max(4−2, 0) = **2**

### 费用汇总

| 费用项 | 计算过程 | 金额 (₽) |
|--------|---------|----------|
| 销售收入 | 12217−12217+12217+12217+12289−15000 | +21,723.00 |
| 平台佣金 | −916.28+916.28−916.28−916.28−921.68+1125.00 | −1,629.24 |
| 物流费 | (−241−7.48)+(−268−7.55)+(−242−12.70)+(−241−7.20)+(−213) | −1,239.93 |
| 支付手续费 | −234.90+234.90−204.82−239.17+294.55 | −357.19 |
| 退货处理费 | (−143−15)+(−144−15) | −317.00 |
| **账面利润** | 21,723 − 1,629.24 − 1,239.93 − 357.19 − 317.00 | **+18,179.64** |

### 广告费

| 类型 | 金额 |
|------|------|
| Promotion (Комбо) | −6,727.27 |
| PPC | −3,021.96 |
| **广告费合计** | **−9,749.23** |

### 货物成本

| 参数 | 值 |
|------|-----|
| Master SKU | KJ-217-GD |
| 成本单价 (CNY) | 381.70 |
| 汇率 | 11.2585 |
| 单件 RUB 成本 | 4,297.37 |
| 净成交数 | 2 |
| **货物成本** | **−8,594.74** |

### 税务

| 项目 | 计算 | 金额 |
|------|------|------|
| 白俄订单 | 0 单 | — |
| 出口订单 | 4 单 | — |
| 进口增值税/单 (CNY) | 59.40 | — |
| 进口增值税/单 (RUB) | 59.40 × 11.2585 | 668.75 |
| 白俄应缴税 | max(0×20%/1.2 − 0×668.75, 0) | 0 |
| **出口退税** | 4 × 668.75 | **+2,675.02** |

### 利润链总览

```
销售收入:          +21,723.00 ₽
平台佣金:           -1,629.24 ₽
物流费:             -1,239.93 ₽
支付手续费:           -357.19 ₽
退货处理费:           -317.00 ₽
──────────────────────────────
账面利润:          +18,179.64 ₽
广告费:             -9,749.23 ₽
──────────────────────────────
扣广告后:           +8,430.41 ₽
货物成本:           -8,594.74 ₽
──────────────────────────────
税前毛利:             -164.33 ₽
白俄增值税:               0.00 ₽
出口退税:           +2,675.02 ₽
──────────────────────────────
税后净利:           +2,510.69 ₽

税后利润率:            11.6%
```

---

## 九、Excel 输出格式

### Sheet 1: SKU_Report

| 列 | 字段名 | 说明 |
|----|--------|------|
| A | SKU | Ozon 商品编号 |
| B | 品号 / Артикул | Master SKU |
| C | 商品名称 / Название товара | 截断至 35 字符 |
| D | 销售收入 / Выручка | 正数 |
| E | 平台佣金 / Комиссия Ozon | 负数 |
| F | 物流费 / Доставка | 负数 |
| G | 支付手续费 / Эквайринг | 负数 |
| H | 出货费 / Отгрузка | 负数 |
| I | 打包费 / Упаковка | 负数 |
| J | 退货处理费 / Обработка возврата | 负数 |
| K | 退货退款 / Возврат денег | 负数 |
| L | 临时仓储 / Врем. хранение | 负数 |
| M | 残次品处理 / Списание брака | 负数 |
| N | 越库费 / Кросс-докинг | 负数 |
| O | 客户下单数 / Заказано | 整数 |
| P | 净成交数 / Чистые продажи | 整数 |
| Q | 退货笔数 / Возвратов | 整数 |
| R | 广告费 / Реклама | 负数 |
| S | 广告费占比 / Доля рекламы, % | 百分比 |
| T | 账面利润 / Маржа Ozon | 正/负数 |
| U | 扣广告后 / Маржа после рекламы | 正/负数 |
| V | 白俄订单 / Заказы в РБ | 整数 |
| W | 出口订单 / Заказы на экспорт | 整数 |
| X | 货物成本 / Себестоимость | 负数 |
| Y | 白俄增值税 / НДС РБ | 负数 |
| Z | 出口退税 / Возмещение НДС (экспорт) | 正数 |
| AA | 税前毛利 / Прибыль до налогов | 正/负数 |
| AB | 税后净利 / Чистая прибыль | 正/负数 |
| AC | 税后利润率 / Рентабельность, % | 百分比 |

**排序**：按"税后净利"降序。

**格式**：
- 表头冻结（A2 起冻结窗格）
- 列宽自适应（CJK 字符 ×2.0 权重）
- 数字格式：`#,##0.00`

**底部附加**：未分摊费用清单（跳过 2 行后列出）。

### Sheet 2: Report（汇总报告）

两列布局：
- A列：项目名（中俄双语）
- B列：金额

内容分区：
1. 基本信息（周期、汇率）
2. SKU/订单统计
3. 收入
4. 已分摊费用（佣金→越库费 + 平台费合计）
5. 广告费（Promotion + PPC + 合计）
6. 平台+广告合计
7. 货物成本
8. 税务（白俄税 + 出口退税）
9. 未分摊费用明细 + 合计
10. 利润（税前→税后→利润率）
11. 税后净利（含未分摊）+ 利润率

### Sheet 3: 广告费分类

| 列 | 字段 |
|----|------|
| A | SKU |
| B | 品号 / Артикул |
| C | Promotion / Продвижение |
| D | PPC / Оплата за клики |
| E | 广告费合计 / Реклама, итого |

### Sheet 4: 订单目的国

| 列 | 字段 |
|----|------|
| A | SKU |
| B | 品号 / Артикул |
| C | 商品名称 |
| D | 白俄订单数 |
| E | 出口订单数 |

仅列出有白俄或出口订单的 SKU。

---

## 十、修正历史

### v5 (2026-05-13) — 当前版本

**重大变更**：

1. **广告费归属重构**
   - PPC：从 campaign_objects（当前快照不可靠）迁移到 `/statistics/json` per-SKU 精确数据
   - 引入 `totals.moneySpent` 作总额 + `rows` 按比例归一化，消除 by-day 与归属之间的舍入误差
   - Promotion：从 `orders/generate` 迁移到 `products/generate`（直接 per-SKU 聚合，更精确）

2. **费用归集**
   - 新增 v1 API 兼容（SaleRevenue, SaleCommission, Logistic 等英文 type_name）
   - 新增 `Cancellation`, `PartialReturn`, `LastMilePickUpPoint`, `DeliveryToHandoverPlaceByOzon` 等费用类型
   - Acquiring 从 posting 匹配归属（之前仅比例分摊）

3. **货物成本**
   - 引入 `rate_buffer_pct` 汇率缓冲（3%）
   - 净成交数改用 `max(下单−退货, 0)` 替代 `sales_count`

4. **计数修正**
   - 同一 posting 正负相抵不再计入成交（net=0 → 仅下单+退货，不形成 sales）
   - 老单退货仅负行，从退货数扣除

5. **目的地 & 税务**
   - 新增 `order_destination_v2.json` 缓存（Ozon API 查询）
   - 白俄税公式：`max(收入÷1.2×20% − 单数×进口增值税×汇率, 0)`
   - 出口退税公式：`出口单数 × 进口增值税 × 汇率`

6. **未分摊**
   - 新增 `AcceleratedReviewCollection`、`DefectFineShipmentDelayRate`、`Placements`
   - Acquiring缺口检测

7. **CrossDock**
   - 从比例分摊改为 supply-order API 链精确归属

### v4 (2026-05-05)

- 首次引入目的地拆分（白俄/出口），但使用 `order_destination.json`（仅 posting prefix 匹配）
- PPC 归集使用 campaign_objects（当前快照，存在历史偏差）
- 货物成本使用 `sales_count`（净正 posting 数）计算

### v3 (2026-05-01)

- 支持多 SKU 订单均摊（v3 API 的 `Доставка покупателю` 含商品信息JSON）
- 引入 CrossDock 比例分摊
- 首版 Excel 四表输出

### v2 (2026-04-28)

- 基于 v3 API（俄文 type_name）
- 仅直接归属，无 posting 匹配
- 无广告费拆分

### v1 (2026-04-25)

- 初版：CSV 导入 → 按 SKU 聚合收入/费用
