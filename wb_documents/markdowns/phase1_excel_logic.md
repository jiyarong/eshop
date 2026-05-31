# WB Phase1 利润归集 Excel — 逻辑溯源

来源项目：`/Users/jiyarong/Downloads/ecommerce-analytics/wildberries`
对应输出：`output/worldchoice/reports/xlsx/{period}_WB_Phase1_利润归集.xlsx`

---

## 执行入口

```bash
python scripts/phase1_report.py --store worldchoice --date-from 2026-05-11 --date-to 2026-05-17
```

5 步流程：

| 步 | 代码 | 做什么 |
|---|---|---|
| 1 | `fetcher.fetch_and_save()` | POST `/api/finance/v1/sales-reports/detailed` → 拉财务明细 JSON |
| 2 | `fetcher.get_rub_byn_rate(mid_date)` | CBR 央行 XML → 取**期间中点日**汇率 |
| 2 | `fetcher.fetch_storage_report()` | GET `/api/v1/paid_storage` 三步异步 → 仓储费（RUB） |
| 2 | `fetcher.fetch_ad_settlement()` | GET `/adv/v1/upd` + `/api/advert/v2/adverts` → 广告费（RUB），多SKU活动用 fullstats 按比例拆 |
| 3 | `attribution.attribute_costs()` | 按 nmId + reportType 归集费用 |
| 4 | `profit.compute_profit()` | 查成本表，计算货物成本/税/净利 |
| 5 | `generate_excel()` | 写 xlsx |

---

## Excel 列逐列溯源（OSN税制，共26列）

### 基础信息（A-F）

| 列 | 中文名 | 来源字段 | 说明 |
|---|---|---|---|
| A | nmId | API `nmId` | WB 商品ID |
| B | 品号 | API `vendorCode` | 从财务记录或 shkId 映射取 |
| C | 品牌 | API `brandName` | |
| D | 类目 | API `subjectName` | |
| E | 商品名称 | API `title` | 截断50字符 |
| F | 区域 | reportType | 1=白俄，2=出口 |

### 销量（G-I）

| 列 | 中文名 | 计算逻辑 |
|---|---|---|
| G | 下单数 | `op=="Продажа"` 的 `quantity` 累加 |
| H | 退货 | `op=="Возврат"` 的 `quantity` 累加 |
| I | 净销量 | `max(下单数 - 退货, 0)` |

### 收入（J-L）

| 列 | 中文名 | 计算逻辑 |
|---|---|---|
| J | 标价收入 | `retailAmount × quantity`（仅 Продажа，参考） |
| K | 佣金(参考) | `ppvzSalesCommission`（参考，已含在 forPay，不计入净利） |
| L | 结算额 | Продажа: `+forPay`；Возврат: **`-forPay`**（退货正数要减）|

### 费用（M-S）— 展示列，部分不计入 net

| 列 | 中文名 | API字段 | 是否计入 net |
|---|---|---|---|
| M | 收单费 | `acquiringFee` | **否**（已含在 forPay 里，展示用）|
| N | 配送费 | `deliveryService`（op==Логистика）| 是 |
| O | 自提点费用 | `logistics_reimb + pickup_cost`（Возмещение 类，仅白俄）| **否**（WB内部调整）|
| P | 补收运费 | `rebillLogisticCost`（仅白俄）| **否**（WB内部调整）|
| Q | 仓储费 | 财务 `paidStorage`（白俄）+ 仓储API `warehousePrice`/汇率（归Type2）| 是 |
| R | 罚款 | `penalty`（op==Штраф，仅白俄）| **否**（展示，不计入 net）|
| S | 广告费 | 广告API RUB ÷ 隐含汇率，按销量比例分摊 | 是 |

### 账面小计（T）

```
net = settlement - delivery_cost - storage_cost - deduction_cost - ad_cost
```

**收单费、罚款、logistics_reimb、rebill、pickup 不计入 net。**

### 利润列（U-Z，OSN）

| 列 | 中文名 | 计算逻辑 |
|---|---|---|
| U | 税基(折后标价) | `retailPriceWithDisc × qty`（API单价 × 数量累加）|
| V | 进口VAT/件(CNY) | 从 `wb_master_sku_costs.csv` 查 vendorCode 对应的 `进口增值税20%_CNY` |
| W | 货物成本 | `净销量 × total_cost_cny × (rate_cny_rub × 1.03 / rub_byn_rate)` |
| X | 税前毛利 | `net - 货物成本` |
| Y | VAT净额 | `税基 × 20/120 - 净销量 × import_vat_cny × 有效汇率` |
| Z | 税后净利 | `税前毛利 - VAT净额` |

### 汇总区块

| 区块 | 逻辑 |
|---|---|
| 合计行 | Excel SUM 公式 |
| 未分摊费用 | `unallocated` 列表按 `bonusTypeName` 分组，累加 `paidStorage + deduction + penalty` |
| 扣除未分摊后净利 | `=税后净利合计 - 未分摊合计`（Excel公式）|

---

## 汇率与 1.03 缓冲

```python
# 有效汇率（用于货物成本）
rate_cny_byn = rate_cny_rub * 1.03 / rub_byn_rate

# rate_cny_rub = 10.9306（硬编码常量）
# rub_byn_rate = CBR 中点日原始汇率（无缓冲）
# 1.03 = 运费/清关损耗缓冲
```

---

## 成本查找链（profit.py: lookup_cost）

1. `shared/data/wb_master_sku_costs.csv`（主表，`货物成本_CNY` + `进口增值税20%_CNY`）
2. `shared/data/sku_cost_map.json`（fallback）
3. `_vc_to_master()` 硬编码 vendorCode → Master SKU 映射

---

## 行生成规则

- 每个 SKU 最多 2 行（白俄/出口）
- 某区域 settlement、delivery_cost、net 全部 ≈ 0 → 跳过该行
- 排序：白俄+出口税后净利之和，从高到低

---

## 未分摊进入条件

- `nmId = 0` 的记录
- `shkId` 反查失败的记录
- 典型：广告 Удержание（nmId=0，已被广告API替换）、Джем 订阅费等
