# SKU 成本表结构设计

## 背景

基于现有「成本模板」Google Sheet（含公式），将 SKU 成本数据结构化落库，支持按平台、配送模式、公司规模四个维度计算每个 SKU 的成本与利润。

---

## 设计原则

读取成本模板的单元格公式后，对原设计做了三处修正：

1. **计算字段不落库**：`货物成本`、`进口增值税`、`包装容量`、`平台运费`、`退货分摊` 均可由其他字段推算，不存入数据库。
2. **WB 运费不需要手填**：WB 基础运费由公式 `(体积L - 1) × 14 + 60` 自动推导，只需存包装尺寸。
3. **进口增值税税基只含采购价和关税**：公式为 `(采购价 + 关税) × 20%`，不含运费和清关费。

---

## 表一：`ec_sku_costs`（每个 SKU 一条）

只存**原始输入参数**，所有计算结果在运行时推导。

| 字段 | 类型 | 说明 |
|------|------|------|
| `offer_id` | string, 唯一 | SKU 编码，如 KJ-228-BK |
| `product_name` | string | 商品名称 |
| `purchase_price_cny` | decimal | 国内采货价 / 件（含税到火车站） |
| `freight_to_by_cny` | decimal | 到白俄运费 / 件（按外箱体积换算） |
| `customs_misc_cny` | decimal | 清关杂费 / 件 |
| `customs_duty_rate` | decimal | 关税率，默认 0.10（公式：采购价 × 关税率） |
| `import_vat_rate` | decimal | 进口增值税率，默认 0.20（公式：(采购价 + 关税) × 税率） |
| `pkg_length_cm` | decimal | 外包装长（cm） |
| `pkg_width_cm` | decimal | 外包装宽（cm） |
| `pkg_height_cm` | decimal | 外包装高（cm） |
| `damage_rate` | decimal | 货损率，如 0.01 |
| `misc_cost_cny` | decimal | 杂费 / 件 |
| `memo` | text | 备注 |

**由表一推导（运行时计算）：**

```
customs_duty_cny  = purchase_price_cny × customs_duty_rate
import_vat_cny    = (purchase_price_cny + customs_duty_cny) × import_vat_rate
goods_cost_cny    = purchase_price_cny + freight_to_by_cny + customs_misc_cny
                  + customs_duty_cny + import_vat_cny
pkg_volume_l      = pkg_length_cm × pkg_width_cm × pkg_height_cm ÷ 1000
```

---

## 表二：`ec_sku_platform_costs`（每个 SKU × 场景一条）

唯一索引：`(offer_id, platform, delivery_mode, company_type)`

每个 SKU 最多 8 个场景（2 平台 × 2 配送模式 × 2 公司类型），实际常用 4～6 个。

### 维度字段

| 字段 | 枚举值 | 说明 |
|------|-------|------|
| `offer_id` | — | 关联 ec_sku_costs |
| `platform` | `wb` / `ozon` | 平台 |
| `delivery_mode` | `fbo` / `fbs` | 配送模式 |
| `company_type` | `general` / `small` | 一般纳税人 / 小规模 |

### 平台运费参数

| 字段 | 类型 | 说明 |
|------|------|------|
| `logistics_coeff` | decimal | 仓库运费系数，如 1.55；WB 各仓不同，OZON 填 1.0 |
| `fbo_delivery_cny` | decimal | FBO 送仓费（CNY）；FBS 填 0 |

> **WB 基础运费公式**（由 pkg_volume_l 自动推导，不用手填）：
> `base_logistics_rub = (pkg_volume_l - 1) × 14 + 60`
>
> **平台运费**：
> `platform_freight_cny = base_logistics_rub × logistics_coeff ÷ exchange_rate + fbo_delivery_cny`

### 退货参数

| 字段 | 类型 | 说明 |
|------|------|------|
| `return_rate` | decimal | 退货率；FBO 约 0.10，FBS 约 0.18（来自公式） |

> **退货分摊 / 件**：
> `return_cost_cny = platform_freight_cny × return_rate ÷ (1 − return_rate)`
>
> 逻辑：成交的每件商品共同分摊退货件产生的来回运费。

### 其他平台费用

| 字段 | 类型 | 说明 |
|------|------|------|
| `storage_30d_cny` | decimal | 30 天存储费（CNY）；FBS 填 0 |
| `acquiring_rate` | decimal | 收单费率，约 0.015 |
| `commission_rate` | decimal | 平台佣金率；WB 约 21%，OZON 约 7.5%（按商品类目不同） |
| `ad_spend_rate` | decimal | 广告费率（占售价比例），建议控制在 10% 以内 |

### 税务

| 字段 | 类型 | 说明 |
|------|------|------|
| `sales_tax_rate` | decimal | 一般纳税人填 `null`（用公式计算）；小规模填 0.06 |

> **一般纳税人**（增值税抵扣）：
> `sales_tax_cny = revenue_cny × 20 ÷ 120 − import_vat_cny`
>
> **小规模**（营业税，无抵扣）：
> `sales_tax_cny = revenue_cny × sales_tax_rate`

### 汇率与目标价

| 字段 | 类型 | 说明 |
|------|------|------|
| `exchange_rate_rub_cny` | decimal | 卢布 / 人民币汇率，定期手动更新 |
| `target_price_rub` | decimal | 目标售价（RUB） |
| `min_price_rub` | decimal | 最低可接受售价（RUB） |

---

## 完整计算公式

```
# 表一推导
customs_duty_cny  = purchase_price_cny × customs_duty_rate
import_vat_cny    = (purchase_price_cny + customs_duty_cny) × import_vat_rate
goods_cost_cny    = purchase_price_cny + freight_to_by_cny + customs_misc_cny
                  + customs_duty_cny + import_vat_cny
pkg_volume_l      = pkg_length_cm × pkg_width_cm × pkg_height_cm ÷ 1000

# 表二推导
revenue_cny           = target_price_rub ÷ exchange_rate_rub_cny
base_logistics_rub    = (pkg_volume_l - 1) × 14 + 60          # WB 专用公式
platform_freight_cny  = base_logistics_rub × logistics_coeff ÷ exchange_rate + fbo_delivery_cny
return_cost_cny       = platform_freight_cny × return_rate ÷ (1 − return_rate)
acquiring_cny         = revenue_cny × acquiring_rate
commission_cny        = revenue_cny × commission_rate
ad_spend_cny          = revenue_cny × ad_spend_rate
damage_cost_cny       = goods_cost_cny × damage_rate

# 税务（按公司类型分支）
if company_type == 'general'
  sales_tax_cny = revenue_cny × 20 ÷ 120 − import_vat_cny    # 进项税抵扣
else
  sales_tax_cny = revenue_cny × sales_tax_rate                 # 小规模 6%

# 汇总
total_cost_cny = goods_cost + platform_freight + return_cost + storage_30d
               + acquiring + commission + ad_spend + sales_tax
               + damage_cost + misc_cost

profit_cny  = revenue_cny − total_cost_cny
margin      = profit_cny ÷ revenue_cny
```

---

## 场景示例（KJ-228-SV，WB / FBO / 一般纳税人）

**表一输入：**

| 字段 | 值 |
|------|-----|
| purchase_price_cny | 325 |
| freight_to_by_cny | 22.5 |
| customs_misc_cny | 2.58 |
| customs_duty_rate | 0.10 |
| import_vat_rate | 0.20 |
| pkg_length/width/height | 78 × 52 × 5 cm |
| misc_cost_cny | 2 |

**表一推导：**

| 项目 | 值 |
|------|-----|
| customs_duty_cny | 325 × 0.10 = 32.5 |
| import_vat_cny | (325 + 32.5) × 0.20 = 71.5 |
| goods_cost_cny | 325 + 22.5 + 2.58 + 32.5 + 71.5 = **454.1** |
| pkg_volume_l | 78 × 52 × 5 ÷ 1000 = **20.3 L** |

**表二输入：**

| 字段 | 值 |
|------|-----|
| logistics_coeff | 1.55 |
| fbo_delivery_cny | 12 |
| return_rate | 0.10 |
| acquiring_rate | 0.015 |
| commission_rate | 0.21 |
| ad_spend_rate | 0.043 |
| exchange_rate_rub_cny | 11.7 |
| target_price_rub | 11681 |

**表二推导（成本拆解）：**

| 项目 | 金额（CNY） |
|------|------------|
| 货物成本 | 454.1 |
| 基础运费 = (20.3−1)×14+60 = 330 RUB × 1.55 ÷ 11.7 | 43.7 |
| FBO 送仓费 | 12.0 |
| 退货分摊 = 55.7 × 0.1 ÷ 0.9 | 6.2 |
| 收单费 | 15.0 |
| 平台佣金（21%） | 210.0 |
| 广告费 | 42.9 |
| 销售增值税 = 998×20÷120 − 71.5 | 94.8 |
| 杂费 | 2.0 |
| **总成本** | **880.7** |
| 售价（11681 ÷ 11.7） | 998 |
| **利润** | **117.3（11.75%）** |

---

## 待确认问题

1. **OZON 运费公式**：OZON 的基础运费结构与 WB 不同，`(volume-1)×14+60` 不适用。OZON FBO 送仓费目前按固定值手填，是否需要单独维护 OZON 的运费算法？
2. **FBS 退货率 18%**：来自成本模板公式 `(S2*18%/82%)/AD2`，需确认这个比例是否准确反映实际业务。
3. **汇率更新频率**：汇率存在每一行，批量更新时执行一条 SQL 即可。如需自动拉取实时汇率，可后续接入汇率 API。
4. **历史成本留存**：进货价涨价后，老库存是否需要按旧成本核算？若需要，建议给本表加 `effective_from` 和 `effective_to` 字段支持历史版本。
