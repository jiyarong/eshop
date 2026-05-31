# 电商利润归集系统 — 测试用例（5级递增）

> 项目: ecommerce-analytics
> 测试周期: W19 (2026-05-04 ~ 2026-05-10)
> 数据源: Ozon Seller API v1 /by-day realization CSV
> 测试数据版本: realization_v1_2026-05-10.csv (409行)
> 编写日期: 2026-05-13

---

## 测试级别总览

```
Level 1 → API 响应验证     (数据拉取完整性、类型/金额校验)
Level 2 → 费用归集          (单SKU逐笔费用归属正确性)
Level 3 → 计数逻辑          (下单/退货/净成交笔数)
Level 4 → 广告费分摊        (PPC按campaign映射 + Promotion归因)
Level 5 → 完整利润链        (收入→平台费→广告→货物成本→税务→税后净利)
```

---

## Level 1: API 响应验证

### 目的
验证从 Ozon API 拉取的原始数据完整性：行数、费用类型、金额一致性，以及 PPC statistics/json 与 products/generate 的交叉校验。

### 1.1 /v3/finance/realization (by-day CSV) 响应验证

**输入**: 对 Ozon Seller API v1 发起 GET /v3/finance/realization，周期 W19 (2026-05-04 ~ 2026-05-10)，返回 CSV 文本。

**期望输出**:
- 总行数（含表头）: 410 行（数据行 409 行）
- 唯一费用类型 (type_name): 17 种
  - SaleRevenue, SaleCommission, Logistic, LastMileCourier,
    Acquiring, ClientReturn, PartialReturn, Cancellation,
    DeliveryToHandoverPlaceByOzon, Drop-Off, Shipment,
    TemporaryPlacement, TemporaryPlacementsAgent,
    ReturnStorageInTheWarehouse, PickUpPointReturnAcceptance,
    PayPerClick, Promotion
- SaleRevenue 行数: 62 行（含正收入 + 退货负数）
- SaleRevenue 正数合计: 324,592 ₽
- SaleRevenue 全部行代数和: 总体正值减去退货
- PayPerClick 行数: 15 行（对应 15 个 campaign）
- PayPerClick 合计: 27,226.01 ₽
- Promotion 行数: 11 行（对应 11 个 SKU）
- Promotion 合计: 35,069.56 ₽

**验证方法**:
```bash
# 行数
wc -l data/snapshots/ozon/realization_v1_2026-05-10.csv
# 预期: 410

# 唯一费用类型
cut -d',' -f3 realization_v1_2026-05-10.csv | sort -u | wc -l
# 预期: 17

# SaleRevenue 统计
grep 'SaleRevenue' realization_v1_2026-05-10.csv | wc -l
# 预期: 62
awk -F',' '$3=="SaleRevenue" && $4>0 {s+=$4} END{print s}' realization_v1_2026-05-10.csv
# 预期: 324592

# PayPerClick 统计
grep 'PayPerClick' realization_v1_2026-05-10.csv | wc -l
# 预期: 15
awk -F',' '$3=="PayPerClick"{s+=$4} END{print s}' realization_v1_2026-05-10.csv
# 预期: -27226.01（负数，取绝对值为支出）

# Promotion 统计
grep 'Promotion' realization_v1_2026-05-10.csv | wc -l
# 预期: 11
awk -F',' '$3=="Promotion"{s+=$4} END{print s}' realization_v1_2026-05-10.csv
# 预期: -35069.56
```

**边界条件 / 边缘情况**:
- CSV 编码: UTF-8 with BOM 或纯 UTF-8
- 空字段: 某些行可能缺少 category 字段
- 日期边界: 确保 2026-05-04 00:00:00 ~ 2026-05-10 23:59:59 无遗漏
- 跨日订单: posting_number 同一条可能跨两天出现
- 金额正负: SaleRevenue 退货行金额为负，费用行金额为负

### 1.2 /v1/statistics/json (PPC 汇总) 响应验证

**输入**: 对 Ozon Performance API 发起 POST /v1/statistics/json，campaigns 参数包含全部 15 个 campaign_id，周期 W19。

**期望输出**:
- 15/15 campaign 均返回有效数据
- 所有 campaign 的 total 字段合计 ≈ 27,225.99 ₽
- 与 /by-day PayPerClick 总额 (27,226.01) 差异 ≤ 0.02 ₽
- 差异率 < 0.001%

**验证方法**:
```bash
# 检查 verify_w19.json
cat data/ad_cache/verify_w19.json
# ppc_diff: 0.02 (可接受浮点舍入)
# promo_diff: 0.0
```

**边界条件 / 边缘情况**:
- API 限流: 15 个 campaign 分批请求，每批间隔 ≥ 0.2s
- 空 campaign: 某些 campaign 在 W19 无花费时返回 total=0 或缺失键
- 浮点舍入: JSON 累积求和 vs CSV 浮点列的微小差异（应 < 0.05 ₽）
- campaign_id 不存在: API 返回 404 或空对象，应被跳过而不中断流程

### 1.3 /v1/product/list + /v1/campaign/*/products/generate 响应验证

**输入**: 对 15 个 campaign 逐一调 products/generate，按 SKU 拆分 Promotion 费用。

**期望输出**:
- 涉及 SKU 数量: 11 个
- Promotion 按 SKU 汇总合计: 35,069.56 ₽
- 与 /by-day Promotion 行合计 (35,069.56) 差异 = 0
- 每个 SKU 的 promotion_cost > 0（无挂零 SKU 被遗漏）

**验证方法**:
```bash
# 检查 ad_attribution W19 中所有 promotion_cost 求和
# 预期: 35069.56
python3 -c "
import json
d = json.load(open('data/ad_cache/ad_attribution_2026-05-04_2026-05-10.json'))
total = sum(v['promotion_cost'] for v in d.values())
print(total)
"
# 预期: 35069.56

# 统计有 promotion 的 SKU 数
python3 -c "
import json
d = json.load(open('data/ad_cache/ad_attribution_2026-05-04_2026-05-10.json'))
count = sum(1 for v in d.values() if v['promotion_cost'] > 0)
print(count)
"
# 预期: 11
```

**边界条件 / 边缘情况**:
- 某 campaign 的 products 列表为空 → 跳过，不影响汇总
- 某 SKU 在 goods_map 中不存在 → 记录 warning，不计入
- API 超时 (30s) → 重试 3 次，仍失败则用 /by-day 的 Promotion 行作为降级
- crossdock goods_map 反查: 只对 CrossDock 费用行调用，需查对应日期数据

---

## Level 2: 费用归集（单 SKU 逐笔匹配）

### 目的
验证 attribution.py 对每一行 CSV 数据的费用归属规则是否准确：按 type_name 前缀 → 所属字段，按 posting_number 关联 Acquiring。

### 2.1 SKU 3583393926 — 完整费用链

**输入**:
- CSV 中 posting_number 包含 "65125770-0023" 的 6 行：
```
2026-05-04,0,SaleRevenue,12217.0,3583393926,65125770-0023-1,POSTING
2026-05-04,32,Logistic,-241.0,3583393926,65125770-0023-1,POSTING
2026-05-04,29,LastMileCourier,-7.48,3583393926,65125770-0023-1,POSTING
2026-05-04,69,SaleCommission,-916.28,3583393926,65125770-0023-1,POSTING
2026-05-04,0,SaleRevenue,-12217.0,3583393926,65125770-0023-1,POSTING  ← 退货
2026-05-04,69,SaleCommission,916.28,3583393926,65125770-0023-1,POSTING   ← 佣金返还
```
另有第2笔成交和第2笔退货（同理），以及 Acquiring 手续费行。

**期望输出**:

| 费用项目 | 归属字段 | 来源行 | 金额 (₽) |
|---------|---------|--------|----------|
| 销售收入 (净) | sales_revenue | +12217, -12217, +12217, +12217, +12289, -15000 | +21,723.00 |
| 平台佣金 | commission | -916.28, +916.28, -916.28, -916.28, -921.68, +1125.00 | -1,629.24 |
| 物流费 | delivery_charge | Logistic + LastMileCourier 全部行 | -1,239.93 |
| 支付手续费 | payment_fee | Acquiring 行 ×4 (ITEM类) | -357.19 |
| 退货处理费 | return_delivery | ClientReturn/PartialReturn/Cancellation | -317.00 |

**验证方法**:
1. 导出 attribution.py Phase1 中间结果 JSON，检查 SKU 3583393926 节点。
2. 逐字段与 CSV 手工核对。
3. 用 Excel 报告 Sheet1 (SKU_Report) 中该 SKU 行交叉验证。
4. `/by-day` CSV 中 `grep '3583393926'` 列出所有行，手工求和。

**边界条件 / 边缘情况**:
- SaleRevenue 退货负数: 应正确冲减销售收入，而非计入其他费用
- SaleCommission 退货返还: 应冲减佣金支出（正数 = 退还）
- Acquiring ITEM 行: 仅当 posting_key（前两段）匹配本周期 SaleRevenue 的 posting 时才归属，否则进入"未分摊"
- 老单 Acquiring: 如 posting_key 不在本周期 SaleRevenue 集合中 → 不应归属到该 SKU
- 多笔 Acquiring 同 posting: ITEM 行可能对应多 SKU，按金额比例分摊或按行各自归属
- 同一 posting 多条 SaleRevenue: 如多 SKU 合单，归属于各自 SKU

### 2.2 全局费用分摊校验

**输入**: 整份 CSV (409行) 经过 attribution.py 处理。

**期望输出**:
- 所有 SaleRevenue 行的 posting 都有对应的 Acquiring 被尝试匹配
- 无费用行被遗漏（409行全部分类完毕）
- "未分摊"类别仅含真正无法匹配的行（如老单 Acquiring、缺少 SKU 的行）
- 未分摊合计 = 平台费汇总 - 各 SKU 分摊合计

**验证方法**:
```bash
# 检查 attribution 输出 JSON，遍历所有 SKU 汇总 vs 全局总计
python3 -c "
# 伪代码: sum(sku.fees) + unallocated == total_fees
"
```

**边界条件 / 边缘情况**:
- 费用类型缺失: type_name 不在已知前缀表中 → 归入"其他/未分类"
- SKU 为空: 费用行无 SKU 且无 posting → 进入未分摊
- type_id 优先于 type_name: 系统应优先用 type_id (数字) 匹配，fallback 到 type_name

---

## Level 3: 计数逻辑

### 目的
验证下单数 (заказано)、退货数 (возвратов)、净成交数 (чистые продажи) 的统计规则。

### 计数规则
- **下单数**: SaleRevenue 全部行数（含正收入 + 退货负数），即该 SKU 在周期内出现的 posting 条数
- **退货数**: SaleRevenue 中金额 < 0 的行数（即退货/取消导致的负收入）
- **净成交数**: 下单数 - 退货数（即正收入行数）

### 3.1 SKU 3583393926

**输入**: CSV 中 SKU=3583393926 的全部 SaleRevenue 行（6行）。

**期望输出**:
- 下单数: 4（4笔正收入行: 12217×2 + 12217×2 + 12289 + ? 实际4笔正）
- 退货数: 2（2笔负收入行: -12217, -15000）
- 净成交数: 2（4 - 2 = 2，即最终确认成交 2 单）

**验证方法**: Excel SKU_Report Sheet 的 O/P/Q 列。

### 3.2 SKU 3251594353

**输入**: CSV 中 SKU=3251594353 的 SaleRevenue 行。

**期望输出**:
- 下单数: 6
- 退货数: 1
- 净成交数: 5

### 3.3 SKU 3590321007

**输入**: CSV 中 SKU=3590321007 的 SaleRevenue 行。

**期望输出**:
- 下单数: 6
- 退货数: 1
- 净成交数: 5

### 3.4 全周期 W19 汇总

**输入**: CSV 全部 SaleRevenue 行（62行）。

**期望输出**:
- 总下单数: 62
- 总退货数: 4
- 总净成交数: 58

**验证**: Excel Report Sheet 的 SKU/订单统计区域，各 SKU O列求和 = 62，Q列求和 = 4。

**边界条件 / 边缘情况**:
- 同一 posting 多 SKU: 如合单中 A SKU 的 SaleRevenue 一行，B SKU 的 SaleRevenue 一行，各自计 1 单 → 正确
- posting_number 含多段: 如 `65125770-0023-1`，仅取前两段 (`65125770-0023`) 作为 posting_key
- 退货行无对应正收入: 如跨周期退货（上周期收入、本周期退货），仍计入本周期退货数
- 金额为 0 的 SaleRevenue: 不应出现；若出现视为无效行

---

## Level 4: 广告费分摊

### 目的
验证 PPC 按 campaign→SKU 的精确映射，以及 Promotion 按 products/generate 的 SKU 归因。

### 4.1 PPC 分摊 — Campaign 到 SKU 映射

**输入**:
- /v1/statistics/json 返回 15 个 campaign 的 total 花费
- /v1/campaign/*/products 返回各 campaign 的关联 SKU
- 分摊策略: 单 campaign 多 SKU 时按比例分配（基于各 SKU 在 campaign 中的日均花费占比）

**靶心案例: Campaign 24467978 → SKU 3583442225**

**输入明细**:
- campaign_id = 24467978
- statistics/json 返回 total = 5,540.60 ₽
- goods_map 查询: 该 campaign 绑定 SKU 3583442225

**期望输出**:
- PPC 分摊到 SKU 3583442225: 5,540.60 ₽
- 该 campaign 无误差（100% 归属单一 SKU）

**验证方法**:
```bash
cat data/ad_cache/ppc_json_2026-05-04_2026-05-10.json | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('Campaign 24467978 ->', d['ppc_by_campaign']['24467978'])
print('SKU 3583442225 total PPC ->', d['ppc_per_sku']['3583442225'])
"
# 预期:
# Campaign 24467978 -> {'3583442225': 5540.6}
# SKU 3583442225 total PPC -> 5540.6
```

**边界条件 / 边缘情况**:
- 单 campaign 多 SKU: campaign 25228823 → SKU 3977734025 (2,877.20) + 3979786516 (1,961.70)，合计 = 4,838.90，与 statistics/json 一致
- campaign 无关联 SKU: goods_map 查询为空 → 进入"未分摊广告"
- campaign 费用为 0: statistics/json total = 0 → 不参与分摊，不报错
- 跨周期 campaign: campaign 可能贯穿多周，仅对 statistics/json 返回的当周数值分摊

### 4.2 Promotion 归因 — products/generate 拆分

**靶心案例: SKU 3583393926**

**输入**:
- 涉及 3583393926 的 campaign 可能有多个
- 每个 campaign.products/generate 返回该 SKU 的 promotion 花费

**期望输出**:
- Promotion 归到 3583393926: 6,727.27 ₽
  - комбо (combo promotion): 6,727.27 ₽
  - cpo (cost per order): 0.00 ₽（该 SKU 无 cpo 活动）
- 与 /by-day 中 SKU 3583393926 对应的 Promotion 行一致

**验证**:
```bash
cat data/ad_cache/ad_attribution_2026-05-04_2026-05-10.json | python3 -c "
import json,sys
d=json.load(sys.stdin)
print(d['3583393926']['promotion_cost'])
"
# 预期: 6727.27
```

### 4.3 全局广告费汇总

**输入**: ad_attribution JSON (13 个有广告费的 SKU + 2 个仅 PPC 无 Promotion 的 SKU)。

**期望输出**:
- PPC 合计: 27,225.99 ₽（与 /by-day 差异 0.02）
- Promotion 合计: 35,069.56 ₽
- 广告费总计: 62,295.55 ₽ ~ 62,295.57 ₽

**SKU 广告费清单**:

| SKU | Promotion | PPC | 合计 |
|-----|-----------|-----|------|
| 3979786516 | 760.00 | 2,300.53 | 3,060.53 |
| 3977734025 | 5,628.00 | 3,980.97 | 9,608.97 |
| 3590321007 | 3,600.00 | 721.06 | 4,321.06 |
| 3590307092 | 4,950.00 | 3,063.95 | 8,013.95 |
| **3583442225** | **3,689.70** | **5,540.60** | **9,230.30** |
| 3583394599 | 1,045.00 | 1,713.92 | 2,758.92 |
| 3583443288 | 3,600.70 | 95.47 | 3,696.17 |
| **3583393926** | **6,727.27** | **3,021.96** | **9,749.23** |
| 2639989504 | 350.00 | 2,051.79 | 2,401.79 |
| 3251594353 | 2,144.89 | 3,212.42 | 5,357.31 |
| 3250965434 | 2,574.00 | 1,438.12 | 4,012.12 |
| 3584740118 | 0.00 | 15.93 | 15.93 |
| 3583443109 | 0.00 | 69.27 | 69.27 |
| **合计** | **35,069.56** | **27,225.99** | **62,295.55** |

注: 3584740118 和 3583443109 仅有 PPC 无 Promotion（仅广告、无成交）。

**边界条件 / 边缘情况**:
- 仅广告无成交的 SKU: 广告费应正常记录，但销售收入=0，利润=负广告费
- Promotion 为 0 的 SKU: 不显示在 /by-day Promotion 行中，但 goods_map 中可能出现
- 舍入误差: PPC JSON total (27,225.9899...) vs /by-day (27,226.01) 有 0.02 差异，属于浮点累积误差，应在断言中使用 `abs(diff) < 0.05` 而非 `== 0`

---

## Level 5: 完整利润链（端到端）

### 目的
验证从原始 API 数据到 Excel 最终报告的完整利润计算链，包括平台费、广告费、货物成本、白俄增值税、出口退税。

### 5.1 全局汇总 — W19 完整利润

**输入**: Phase 1 归集 + Phase 2 广告归属 + Phase 3 成本/税务/利润链。

**期望输出**:

```
═══════════════════════════════════════════
            W19 利润链汇总
═══════════════════════════════════════════

一、基本信息
  周期:         2026-05-04 ~ 2026-05-10
  SKU 数:       13（10个有销售 + 3个仅广告）
  汇率:          11.2585 CNY/RUB
  成本单价:      381.70 CNY/SKU (Master: KJ-217-GD)

二、收入
  销售收入:      +324,592.00 ₽

三、平台费用
  佣金、物流、支付手续费等合计:  -134,577.00 ₽

四、广告费
  Promotion:     -35,070.00 ₽  (约数)
  PPC:           -27,226.00 ₽  (约数)
  广告合计:       -62,296.00 ₽  (约数)

五、平台+广告合计:  -196,873.00 ₽  (约数)

六、货物成本
  净成交 58 单 × 4,297.37 ₽:  -126,053.00 ₽  (约数，实际由 net_qty × unit_cost 得出)

七、税务
  白俄订单:      5 单
  出口订单:      53 单
  白俄应缴增值税: -3,089.00 ₽  (约数)
  出口退税:      +18,789.00 ₽  (约数)

八、利润
  税前毛利:      +1,666.00 ₽  (约数，利润率 ≈ 0.5%)
  税后净利:      +17,366.00 ₽  (约数，利润率 ≈ 5.4%)
  含未分摊税后净利: +15,757.00 ₽  (约数，利润率 ≈ 4.9%)
═══════════════════════════════════════════
```

**精确数值**（来自用户上下文）:
- 销售收入: 324,592 ₽
- 平台费合计: -134,577 ₽
- 广告费合计: -62,296 ₽
- 货物成本: -126,053 ₽
- 税前毛利: 1,666 ₽ (利润率 0.5%)
- 白俄税: -3,089 ₽
- 出口退税: +18,789 ₽
- 税后净利: 17,366 ₽ (利润率 5.4%)
- 含未分摊净利: 15,757 ₽ (利润率 4.9%)
- 白俄订单: 5 单 / 出口订单: 53 单
- 10 SKU 有销售 + 3 SKU 仅广告

**验证方法**:
1. 打开 Excel 文件: `output/reports/xlsx/2026-05-04_2026-05-10_Phase1_SKU利润归集_v5.xlsx`
2. 切换到 Sheet: "Report" (汇总报告)
3. 逐段核对 1~11 区（基本信息→利润）
4. 切换到 Sheet: "SKU_Report"，校验最末行（汇总行）
5. 切换到 Sheet: "订单目的国"，核对白俄/出口单数

**边界条件 / 边缘情况**:
- 未分摊费用: 有些 Acquiring 行因 posting_key 不在本周期内而无法归属 → 应出现在 Report Sheet 的"未分摊"区域，并在最终利润中做含/不含两版
- 货物成本 = 0: 仅广告无成交的 SKU（如 3584740118, 3583443109）
- 白俄税计算: 仅当 SKU 有白俄订单 + 正向利润时才产生
  - 公式: БелНДС = max( revenue_BY × 20% / 1.2 − orders_BY × import_VAT, 0 )
- 出口退税: 仅出口订单产生
  - 公式: Возмещение = orders_export × import_VAT
- 进口增值税单价: 59.40 CNY × 汇率 11.2585 = 668.75 ₽/单
- 成本单价统一: 所有 SKU 共享同一 Master SKU (KJ-217-GD) 的成本价
- 汇率波动: 测试中使用固定汇率 11.2585，生产环境需支持手动输入

### 5.2 单 SKU 完整利润链 — 3583393926 (靶心案例)

**输入**: 前4级验证通过后的所有中间数据。

**期望输出** (逐段):

```
SKU 3583393926 利润链
────────────────────────────────────
销售收入:          +21,723.00 ₽
平台佣金:           -1,629.24 ₽
物流费:             -1,239.93 ₽
支付手续费:           -357.19 ₽
退货处理费:           -317.00 ₽
────────────────────────────────────
账面利润 (Ozon):   +18,179.64 ₽  (= 21723 - 1629.24 - 1239.93 - 357.19 - 317)

广告费:             -9,749.23 ₽   (Promo 6727.27 + PPC 3021.96)
────────────────────────────────────
扣广告后利润:        +8,430.41 ₽

货物成本 (2件):     -8,594.74 ₽   (= 2 × 4297.37)
────────────────────────────────────
税前毛利:             -164.33 ₽   (≈ 0% 利润率)

白俄增值税:              0.00 ₽   (无白俄订单)
出口退税:           +2,675.02 ₽   (4单出口 × 668.75)
────────────────────────────────────
税后净利:           +2,510.69 ₽   (利润率 ≈ 11.6%)
```

**验证**: Excel SKU_Report Sheet 中 SKU=3583393926 的 T ~ AB 列。

### 5.3 订单目的国统计

**输入**: order_destination_v2.json (267条记录)。

**期望输出** (W19):
- 白俄订单: 5 单 (is_belarus=true)
- 出口订单 (俄联邦): 53 单 (is_belarus=false)
- 总计: 58 单 = 净成交数 ✓

**验证**:
```bash
python3 -c "
import json
d = json.load(open('data/order_destination_v2.json'))
bel = sum(1 for v in d.values() if v.get('is_belarus'))
exp = sum(1 for v in d.values() if not v.get('is_belarus'))
print(f'白俄: {bel}, 出口: {exp}, 总计: {bel+exp}')
"
# 预期: 白俄: 31? (全量267条的历史累计, W19周期内5单需要过滤posting)
```

注意: order_destination 包含历史全量数据，需按 W19 周期内的 posting_number 过滤。

**边界条件 / 边缘情况**:
- destination 缺失: 某些 posting 可能无目的地记录 → 默认视为出口
- 白俄仓库发货但目的地为俄: 按 is_belarus 字段判断，不以 warehouse 为准
- 空投递状态: status 不为 "delivered" 的订单不应计入税务计算

---

## 测试执行建议

### 运行顺序
```
Level 1 → API 响应完整性
   ↓
Level 2 → 单SKU费用归集正确性
   ↓
Level 3 → 下单/退货/净成交计数
   ↓
Level 4 → PPC+Promotion 广告费分配合计
   ↓
Level 5 → 端到端利润链 + Excel 输出
```

### 回归测试命令

```bash
# Level 1: API数据完整性
python3 -m pytest tests/test_api_validation.py::TestLevel1 -v

# Level 2: 费用归集
python3 -m pytest tests/test_attribution.py::TestLevel2 -v

# Level 3: 计数
python3 -m pytest tests/test_counting.py::TestLevel3 -v

# Level 4: 广告
python3 -m pytest tests/test_ad_attribution.py::TestLevel4 -v

# Level 5: 完整利润
python3 -m pytest tests/test_full_profit.py::TestLevel5 -v

# 一键全量
python3 -m pytest tests/ -v --tb=short
```

### 测试数据固定
- 所有测试均使用 W19 (2026-05-04 ~ 2026-05-10) 的 snapshot 数据
- 禁止在测试中对 Ozon API 发起真实网络请求（使用 mock 或 snapshot 文件）
- 基准数据集路径: `data/snapshots/ozon/realization_v1_2026-05-10.csv`

---

## 附录: 费用类型对照表 (v1 英文 → 归属字段)

| type_id | type_name | 归属字段 | 匹配方式 |
|---------|-----------|---------|---------|
| 0 | SaleRevenue | sales_revenue | 直接归属 (SKU) |
| 1 | Acquiring | payment_fee | posting 匹配 |
| 29 | LastMileCourier | delivery_charge | 直接归属 (SKU) |
| 32 | Logistic | delivery_charge | 直接归属 (SKU) |
| 69 | SaleCommission | commission | 直接归属 (SKU) |
| 98 | DeliveryToHandoverPlaceByOzon | delivery_charge | 直接归属 (SKU) |
| — | ClientReturn | return_delivery | 直接归属 (SKU) |
| — | PartialReturn | return_delivery | 直接归属 (SKU) |
| — | Cancellation | return_delivery | 直接归属 (SKU) |
| — | Drop-Off | delivery_charge | 直接归属 (SKU) |
| — | Shipment | delivery_charge | 直接归属 (SKU) |
| — | TemporaryPlacement | storage_fee | 直接归属 (SKU) |
| — | TemporaryPlacementsAgent | storage_fee | 直接归属 (SKU) |
| — | ReturnStorageInTheWarehouse | storage_fee | 直接归属 (SKU) |
| — | PickUpPointReturnAcceptance | return_delivery | 直接归属 (SKU) |
| — | PayPerClick | ppc (广告) | 全局/campaign |
| — | Promotion | promotion (广告) | products/generate |

---

> 文档状态: 初稿
> 所有数值基于 W19 snapshot 数据验证
> 实际执行测试时以 Excel 报告最终数值为准（可能存在 0.01~0.05 浮点差异）
