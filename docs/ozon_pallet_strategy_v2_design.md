# Ozon 打托策略 v2：尺寸分类修正、补货量区间化、箱/托方案择优

日期：2026-10-21。本文是**设计文档**，不含实现改动。所有"现有行为"结论均已在 `main`（`74aa2d4c`）上逐条核对；所有"官方口径"结论均标注了来源文件与行号。

状态：v2 已实现。第 7 节记录本次采用的实现口径与仍未接入的平台数据边界。

---

## 0. 背景与问题陈述

领导提出三条改进意见，本文将其转成可实现的设计：

1. **尺寸分类**：大件与普通件的单边要求有重叠，任一条边超限即升级为大件；120/60/50 是普通（非分拣）的边限制。现有"表格"难用。
2. **补货数量**：只看打托，需综合"补多少件"与"托盘能放多少件"。例：ZJ004 实际能放 18，官方 28 天建议 14，生成 14 未利用充分。补货量应有上下区间而非定死的 28 天缺口；多放 1 个等于免费越库。可能需动态规划。
3. **按箱送 vs 按托送**：存在按箱送的可能，需吃透文档、理解按箱送与按托的逻辑及费用；大量品可能选箱送，仅在明确托盘收益更大时才用托盘。

本文对三点的技术判断（均给出证据）：

- 第 1 点：**成立，且现状是 bug**。现有实现把"非分拣"整档并入 KGT，且边界用了 `>=`（官方含等号）。
- 第 2 点：**洞察成立，但"动态规划"不是正确工具**。这是带背包约束的整数规划；且现有 `@capacities` 原语已提供所需的"单托最大箱数"，用分层贪心即可，无需 DP。
- 第 3 点：**与真实费率数据吻合**。但现状不只是"缺算法"——工作台页面**根本不展示费用**，且平台写入层**硬编码只支持 PALLET**。

---

## 1. 官方口径（事实基础）

### 1.1 Ozon FBO 放置区/尺寸分档

来源：`ozon_wb_docs/ozon-docs` 对应官方页，本文以 2026-10-21 抓取的 `/libra/kgt/fbo/postavka-kgt-fbo` 与 `/libra/fbo/gruzomesta-i-podgotovka-k-otgruzke/k-kakoi-zone-otnositsya-tovar` 为准。

单位 cm / kg，**上限均含等号**（原文 "максимальное значение — включительно"）：

| 档位 | 长（最长边） | 宽（中间边） | 高（最短边） | 重量 |
|---|---|---|---|---|
| 可分拣 сортируемый | ≤ 45 | ≤ 32 | ≤ 32 | ≤ 10 |
| 非分拣 несортируемый | 45–120 | 32–60 | 32–50 | ≤ 35 |
| 大件 КГТ | 45–220 | 32–120 | 32–80 | ≤ 120 |
| 不能走 FBO | > 220 | > 120 | > 80 | > 120 |

**判定语义**：原文 "Если хотя бы одна характеристика соответствует параметрам крупногабаритного или несортируемого товара, он попадёт в эту категорию" —— 任一指标越线即归类，不取平均、不看体积和。

**归一化**：官方定义 длина = 最长边、ширина = 中间边、высота = 最短边。三边必须先降序排序再比表。

**测量对象**：带销售包装的**单件**商品（ОВХ），来源 `/libra/work-with-goods/.../product-information/ovh`："При замере ОВХ не вскрываем упаковку и делаем замер по её габаритам"。

### 1.2 非分拣与大件的实质区别

| 维度 | 非分拣 | 大件 КГТ |
|---|---|---|
| 卡在哪 | 仓储**摆放**（不进标准单元格 ячейка） | 仓储 + **运输 + 费率 + 仓库白名单** |
| 链路 | 常规仓库、常规物流 | 托盘货、专用仓库、独立费率 |
| 官方原文 | "Такие товары не размещаем в стандартных ячейках" | "для перевозки которых не подходит обычный транспорт" |

### 1.3 费用（与本文三条意见直接相关）

来源：`ozon_wb_docs/ozon-docs/commissions-tariffs/commissions-tariffs-ozon/rashody-na-dop-uslugi.md`

- **托盘最低计费体积 1900 L**（`:1061`）："минимальный объём для тарификации палетной поставки — 1900 литров. Если объём меньше — считаем как 1900 л."。**箱装无此下限。**
- 货位体积 = 所有商品体积之和，**向上取整到整数升**。
- 处理费：仓库/СЦ 箱托均 0；ПВЗ 箱 5 ₽/L；ППЗ 箱 4 ₽/L；交快递员箱托均 1.55 ₽/L。**托盘在 ПВЗ/ППЗ 不适用。**
- 仓储费：普通商品 **2.50 ₽/L/天**（`:73`）；大件 КГТ **0.08 ₽/L/天**（`:74`，另见 `:122/161/201` 的 0.10 变体）。**KGT 从转运后第一天即计费**（`:78`）。

### 1.4 箱/托的物理与点位限制

来源：`ozon_wb_docs/ozon-docs/fbo/crossdoking/kross-doking.md`、`docs/20260718-Ozon-WB仓储发货规则知识库.md`

- 仓库：托盘 ≤ 40 个/供货；箱 ≤ 30 个/供货（启用运输货位后 200/1500）。
- **ПВЗ/ППЗ 只收箱，不收托盘**（`kross-doking.md:77`）。
- 例外点位：СЦ Ханты-Мансийск 只收箱；Софьино / Домодедово / МО ТСЦ Новая Рига / Пушкино-1 РФЦ 只收托盘（`kross-doking.md:113`）。
- 箱 ≤ 25 kg；托盘 ≤ 800 kg；含托高 ≤ 2.2 m。

### 1.5 箱/托费率的真实分布（本文实算）

数据源 A（项目库）：`RawOzon::CrossDockTariff`，**1,376 条**，快照 `2026-09-24`。按 `1900 × pallet_rub_per_l / box_rub_per_l` 算盈亏平衡体积：

| 分位 | 平衡体积 |
|---|---|
| p10 | 572 L |
| **p50** | **950 L** |
| p90 | 1,692 L |

数据源 B（官方 CSV）：`ozon_wb_docs/ozon-crossdock-tariffs-2026-09-16.csv`，11,080 行：

| 指标 | 数值 |
|---|---|
| 托盘每升单价 / 箱每升单价（中位数） | 0.606 |
| 托盘单价更低的路线占比 | 94.6% |
| 盈亏平衡体积 p50 | 1,151 L |

**结论**：两个独立数据源给出同量级平衡点（950–1,151 L）。供货体积低于该点按箱更省（因托盘被 1900 L 下限放大），高于该点打托更省。这为第 3 点提供了量化依据。

---

## 2. 现状核对（逐条对照代码）

### 2.1 尺寸分类

**唯一判定实现在** `app/models/ec/sku_dimension.rb`：

```ruby
# :42-53
def self.ozon_size_category_for(length:, width:, height:, weight:)
  values = [length, width, height, weight]
  return OZON_SIZE_CATEGORY_UNKNOWN if values.any? { |v| v.blank? || v.to_d <= 0 }
  length, width, height = values.first(3).map(&:to_d).sort.reverse   # 已正确排序
  weight = values.last.to_d
  return OZON_SIZE_CATEGORY_OVERSIZE if length > 220 || width > 120 || height > 80 || weight > 120
  return OZON_SIZE_CATEGORY_KGT if length >= 45 || width >= 32 || height >= 32   # ← 缺陷
  OZON_SIZE_CATEGORY_NORMAL
end
```

缺陷：
1. **只有 4 个类别值**（`unknown/normal/kgt/oversize`，`:7-16`），**缺"非分拣"**，`>= 45/32/32` 起全部并入 `kgt`；
2. **边界用 `>=`**，与官方"含等号"矛盾——边长恰为 45/32/32 时应为可分拣；
3. **重量未参与非分拣/KGT 分界**：官方 KGT 是 `> 120/60/50 **或** > 35 kg`，现状 36 kg 且三边都小的商品会被判 `normal`。

**阈值三处重复**（改口径必须同步）：
- `app/models/ec/sku_dimension.rb:49-50`
- `db/migrate/20261020013933_recalculate_ozon_size_categories_from_unit_dimensions.rb:19`（SQL，**且未做三边排序**）
- `db/migrate/20261020031211_normalize_ozon_unit_dimension_axes_for_categories.rb:37-38`（Ruby 副本）

**取值口径**：`#calculated_ozon_size_category`（`:33-40`）只用**内包装** `inner_*`，与外箱无关。`WorkbenchQuery`（`:127`）与 `Build`（`:81`）都调它（实时算，不读存量列）。

**分类的下游影响**：
- `packing.rb:76-86` 按类别分组候选、`:119-120` 阻止**不同类别混托**（`mixed_ozon_size_categories`）；
- `workbench_query.rb:98,102` 用 `oversize` 做 FBO 资格与排除原因；
- 展示于 `show.html.erb:70`、`erp/sku_dimensions/index.html.erb:85`。

→ **现状把非分拣误判为 KGT，会导致非分拣货被与大件同组参与候选，而官方两者在仓库走不同区域。**

### 2.2 补货数量

**缺口**（`app/services/ec/ozon_warehouse_recommendation_query.rb:238`）：

```ruby
[(daily_sales * target_days).ceil - available - inbound, 0].max
```

**建议箱数**（`app/services/ec/pallet_plans/workbench_query.rb:99`）：

```ruby
suggested_boxes = fbo_eligible && products.one? ?
  [(shortage.to_d / pcs).ceil, ([allocatable, 0].max / pcs)].min : 0
```

即 `min(ceil(缺口/每箱件数), floor(可分配库存/每箱件数))`，`pcs = dimension.outer_box_pcs`。

**特征**：两次硬取整的**单点值**，`target_days` 默认 28（`build.rb:19`、控制器 `:70`）。**不会利用托盘剩余空间**——领导 ZJ004 的例子（能放 18、建议 14）正是此公式的必然结果。

**关键可用原语**（`app/services/ec/pallet_plans/packing.rb:41-43`）：`prepare_items!` 对每个 SKU 先用 `quantity: nil` 单独算一次，把结果存入

```ruby
@capacities << result[:total_boxes]   # 该 SKU 单托最多能装几箱
```

**这个原语就是第 2 点"托盘能放多少件"的现成答案，无需新算法。**

### 2.3 费用与箱/托对比

**结论：装托工作台链路上不存在任何箱/托费用对比。**

- `PalletPacking::Fees`（`app/services/pallet_packing/fees.rb`）只按 profile 算**单一方案**；`bill_l = [goods_l.ceil, 1900].max`（`:13`）已实现 1900 L 下限，但**没有 box 分支**。
- `docs/ozon_pallet_workbench_implementation_plan.md:165` 明确：首版**"不自动推荐最低运费方案"**。
- **工作台与计划详情页根本不展示费用**：`_result.html.erb` 只有托盘数/箱数/件数；仅独立计算器页 `pallet_calculators/_results.html.erb` 显示费用。

**已存在但未被装托链路引用的能力**：
- `RawOzon::CrossDockTariff#amount_for(volume_l:, package_type:)`（`app/models/raw_ozon/cross_dock_tariff.rb:23-25`）已支持 `"pallet"` / `"box"` 双费率，并有 `for_route(supply_receiving_zone_key, destination_cluster_key)` scope；
- 表 `raw_ozon_cross_dock_tariffs` 有 `box_rub_per_l` / `pallet_rub_per_l` 两列，按"收货区 + 目的集群"唯一索引；
- 调用方目前只有利润测算页（人工点选 `use_pallet` / `use_box`，无自动择优）。

### 2.4 平台写入

`app/services/ec/pallet_plans/ozon_supply_runner.rb:204`：

```ruby
{ key: "#{@plan.plan_no}-#{pallet.position}", value: { type: "PALLET", items: items } }
```

**硬编码 `PALLET`**，整条链路（`Build → Packing → Save → OzonSupplyRunner`）只支持打托。

### 2.5 其他相关事实

- `platform_covered_units`（`ec_pallet_plan_items`）**无任何写入路径**，全库仅校验与读取（`pallet_plan_item.rb:12`、`availability.rb:24,41`），**恒为 0**。故 `Availability` 的 `units - platform_covered_units` 目前等价于 `units`。
- 平台上限（30 箱/40 托/1500 箱运输货位）**代码中无任何强制校验**，仅存在于文案与文档。`Calculator::MAX_PALLETS = 100` 是工程上限。
- `Rules::PROFILES` 无"箱模式" profile；`Packing::PROFILE` 硬编码 `"ozon_fbo"`；`Calculator#validate!` 的 SKU 数硬编码 1..5。

---

## 3. 阶段 1：尺寸分类修正

**性质**：修正缺陷。独立、低风险、可先做。

### 3.1 目标状态

引入第 5 个类别 `non_sortable`，判定语义与官方一致（任一指标越线即归类、边界含等号、重量参与分档）。

### 3.2 判定函数（唯一权威实现）

```ruby
# app/models/ec/sku_dimension.rb
OZON_SIZE_CATEGORY_UNKNOWN      = "unknown".freeze
OZON_SIZE_CATEGORY_NORMAL       = "normal".freeze
OZON_SIZE_CATEGORY_NON_SORTABLE = "non_sortable".freeze   # 新增
OZON_SIZE_CATEGORY_KGT          = "kgt".freeze
OZON_SIZE_CATEGORY_OVERSIZE     = "oversize".freeze
OZON_SIZE_CATEGORIES = [UNKNOWN, NORMAL, NON_SORTABLE, KGT, OVERSIZE].freeze

def self.ozon_size_category_for(length:, width:, height:, weight:)
  values = [length, width, height, weight]
  return OZON_SIZE_CATEGORY_UNKNOWN if values.any? { |v| v.blank? || v.to_d <= 0 }

  l, w, h = values.first(3).map(&:to_d).sort.reverse
  weight   = values.last.to_d

  # 官方上限含等号，故一律用 > 而非 >=
  return OZON_SIZE_CATEGORY_OVERSIZE     if l > 220 || w > 120 || h > 80 || weight > 120
  return OZON_SIZE_CATEGORY_KGT          if l > 120 || w > 60  || h > 50 || weight > 35
  return OZON_SIZE_CATEGORY_NON_SORTABLE if l > 45  || w > 32  || h > 32 || weight > 10

  OZON_SIZE_CATEGORY_NORMAL
end
```

**边界语义核对表**（必须逐条测试）：

| 输入（长/宽/高, kg） | 期望 | 说明 |
|---|---|---|
| 45 / 32 / 32, 10 | `normal` | 恰好等于可分拣上限 |
| 45.01 / 32 / 32, 10 | `non_sortable` | 长边刚越线 |
| 120 / 60 / 50, 35 | `non_sortable` | 恰好等于非分拣上限 |
| 120.01 / 60 / 50, 35 | `kgt` | 长边越非分拣 |
| 30 / 30 / 30, 10.01 | `non_sortable` | **仅重量越非分拣**（现状会误判 normal） |
| 30 / 30 / 30, 35.01 | `kgt` | **仅重量越非分拣**，但未越 KGT 的 120 kg |
| 220 / 120 / 80, 120 | `kgt` | 恰好等于 KGT 上限 |
| 220.01 / 120 / 80, 120 | `oversize` | 超 KGT |
| 30 / 30 / 30, 120.01 | `oversize` | **仅重量越线** |
| 空 / 0 / 负值 | `unknown` | 缺数据 |

### 3.3 阈值收敛（消除三处重复）

新增 `Ec::SkuDimension::OZON_SIZE_LIMITS` 常量作为唯一事实源：

```ruby
OZON_SIZE_LIMITS = {
  oversize:     { length: 220, width: 120, height: 80,  weight: 120 },
  kgt:          { length: 120, width: 60,  height: 50,  weight: 35  },
  non_sortable: { length: 45,  width: 32,  height: 32,  weight: 10  }
}.freeze
```

模型与两个迁移都从此常量读取，杜绝再次漂移。**注意迁移 1 的 SQL 版还缺三边排序**，回填时必须修正（否则长宽倒置的商品会被错判）。

### 3.4 数据回填

- 新建迁移 `RecalculateOzonSizeCategoriesWithNonSortable`，照 `20261020013933` 的模式重算存量 `ec_sku_dimensions.ozon_size_category`；
- SQL 中需先排序三边：`GREATEST(...)` / `LEAST(...)` 或按列重排；
- 迁移的 `down` 需能回退（回到旧的 3 档口径）。

### 3.5 影响面复核

1. **`packing.rb` 的混托规则**：非分拣与大件现在会正确分开，需确认这是期望行为（我判断是——官方两者区域不同），并补测试。
2. **I18n**：新增类别文案，三语齐全：
   - `config/locales/pallet_workbench.{yml,en.yml,ru.yml}` → `categories.non_sortable`（`normal`/`kgt` 段见 `pallet_workbench.yml:109-114`）
   - `config/locales/{zh,en,ru}.yml` → `erp.sku_dimensions.categories.non_sortable`（现段见 `zh.yml:3523-3527`、`en.yml:3311-3315`、`ru.yml:3262-3266`）
3. **`validates ... inclusion`**（`sku_dimension.rb:21`）随 `OZON_SIZE_CATEGORIES` 自动覆盖。
4. **erp 尺寸维护页**（`erp/sku_dimensions/index.html.erb:85`）与 `erp.sku_dimensions.categories.*` 展示需同步。
5. **`workbench_query.rb` 的 `fbo_eligible`**：目前只看 `!= oversize`，非分拣仍可 FBO（正确，非分拣能走 FBO）。

### 3.6 测试

- `test/models/ec/sku_dimension_test.rb`：补 3.2 表格全部边界（现有测试 `:57-74, :96` 已覆盖 `normal/kgt/oversize` 与三边排序，扩展即可）；
- `test/services/ec/pallet_plans/packing_test.rb`：补"非分拣与大件不可混托"；
- 两个迁移测试（`test/migrations/*`）需同步新口径。

### 3.7 验收标准

- 3.2 表格逐条通过；
- 三处阈值均引用 `OZON_SIZE_LIMITS`，grep 无残留字面量；
- 存量数据回填后，抽样商品与后台实际放置区一致；
- `bin/rails test test/models/ec/sku_dimension_test.rb test/services/ec/pallet_plans/ test/services/pallet_packing/` 全绿。

---

## 4. 阶段 2：补货量区间化 + 托盘空间填充

**性质**：行为增强。依赖阶段 1（分类正确才能正确算容量）。

### 4.1 问题形式化

**现状**：`boxes_i = min(ceil(gap_i / pcs_i), floor(avail_i / pcs_i))`，逐 SKU 独立，无托盘耦合。

**目标（2026-10-21 更新）**：在托盘数、路线计费体积及提货/点位处理费不增加的前提下，按当前清单箱数比例增补，不受覆盖天数或销量限制。

**为什么不是动态规划**：这是**带背包约束的整数规划**——决策变量 `boxes_i ∈ Z+`，约束为托盘体积/重量/高度/5-SKU 上限，目标为分层优化。DP 的状态空间在此处不可控且无必要；**分层贪心**即可达到业务目标且可解释、可测试。

### 4.2 分层目标

```
第 1 层：托盘数、路线计费体积及提货/点位处理费不增加
第 2 层：优先保持增补前的 SKU 箱数比例，逐箱试算实际装载
第 3 层：受库存或装载限制的 SKU 暂停，继续尝试其他 SKU
```

**经济依据**：托盘已付 1900 L 下限（`fees.rb:13`），未用满即为已付费的浪费。把 14 箱加到 18 箱而不突破 1900 L 时，**运输费不变**，多出 4 箱直接增加覆盖天数——这正是领导"免费越库"的机制。

“免费空间”限定为托数、路线计费体积以及提货/点位处理费不增加。分拣、仓储按商品量计费，可能随增补上涨，须单独展示增量，不能以包含这些费用的 `known_fee` 不变作为填充条件。

**注意边界**：若填充导致**多开一个托盘**，成本跳变，边际成本不再是 0。故第 1 层"托盘数最少"必须严格优先于第 2 层。此判定基准需领导确认（见 7.1）。

### 4.3 参数设计

| 参数 | 含义 | 默认 | 兼容 |
|---|---|---|---|
| `target_days` | 目标覆盖天数（保留） | 28 | 现有调用不变 |
| `min_days` | 下限，低于此必补 | 21 | 新增，缺省时 = `target_days` |
| `max_days` | 初始建议区间的覆盖上限，不限制增补或 MAX | 35 | 新增，缺省时 = `target_days` |
| `fill_free_space` | 是否按清单比例利用托盘免费空间增补 | true | 新增 |

约束：`min_days ≤ target_days ≤ max_days`，均需 `between?(1, 180)`（沿用 `build.rb:20` 的校验口径）。

### 4.4 新增服务 `Ec::PalletPlans::FillStrategy`

**职责单一**：给定当前清单，输出按原箱数比例增补后的清单，复用已有几何算法。覆盖天数仅用于初始补货建议。

```
输入：items（含 sku_code / 当前箱数 / 每箱件数）、整箱库存上限、
      现有 Packing 结果（含 capacities）、fill_free_space、点位信息
输出：每 SKU 的最终箱数 + 填充说明（哪些 SKU 被加量、为什么、费用是否变化）
```

算法：

```
1. 记录当前清单每个 SKU 的原箱数 original_i
2. 用现有 Packing 算基础方案 → 得到托盘数 P 与费用预算
3. 若 fill_free_space：
     a. 对每个 SKU 求 max_boxes = min(floor(avail / pcs), capacity_i × P, 100000)
     b. 按比例误差边际代价 (2 × 当前箱数 + 1) / original_i 升序逐箱尝试
     c. 同分时按当前增幅、SKU 编码排序；每次重算几何并校验费用预算
     d. 无法增补的 SKU 暂停，其他 SKU 成功增补后重新尝试，直至均不可再加
4. 输出最终清单 + 差异说明
```

**关键约束**：加量必须复用 `Packing`（含 `MAX_SKUS_PER_PALLET = 5` 与类别隔离），不得另写几何。

### 4.5 展示

`_result.html.erb` 需新增"填充说明"区，把决策依据显性化，例如：

> 基础方案 14 箱；按原箱数比例增补至 18 箱，不受覆盖天数或销量限制。托数、路线计费体积及提货/点位处理费不增加，分拣及仓储费用单独显示。

对应 I18n 键位于 `pallet_strategy_v2.yml` 的 zh/en/ru。

初始建议仍按目标缺口向上取整；增补直接使用可分配整箱库存，不再查询销量或计算覆盖上限。增补结果逐 SKU 展示停止原因，区分库存、托盘容量、计费体积、点位处理费和单品体积缺失。无增补时也显示原因，保留原清单。

每个 SKU 箱数旁提供 MAX，保持其他 SKU 数量和当前托数，在整箱库存、剩余重量、外箱体积和单 SKU 容量上界内，从大到小调用 `Packing` 验算实际排布与旋转。单托模式允许修正目标 SKU 当前超量的输入；其他 SKU 仍须通过校验。MAX 不受覆盖天数、销量或免费计费体积限制，费用随结果重算，支持一次撤销；现有装托算法为启发式，不宣称全局最优。

### 4.6 测试

- 单测 `FillStrategy`：断言"填充后托盘数不增加"、"路线计费体积及点位处理费不增加"、"多 SKU 分拣费可随增补上涨且单独显示"、"不突破库存与容量"、"`fill_free_space: false` 时行为与现状一致"；
- 回归 `workbench_query_test.rb`：现有 `suggested_boxes` 断言（`:27-46` 缺口 19/每箱 10 → 2 箱）在 `fill_free_space: false` 下必须保持；
- `build_test.rb` / `packing_test.rb` 的既有数量守恒断言不得破坏。
- `maximize_test.rb` 覆盖混装、重量、排布、旋转、库存、多托及单品体积缺失；预览、保存及前端撤销继续校验数量一致。

### 4.7 验收标准

- 领导 ZJ004 类案例：建议箱数从 14 提升到 18（或容量上限），且费用不变；
- 托盘数与填充前相同；
- 所有既有箱数/件数守恒测试通过。

---

## 5. 阶段 3：箱送 / 托送双方案择优

**性质**：新增能力。使用公开接口 schema 确认 cargo 类型与结构，并用本地模拟完整流程验收。

### 5.1 现状差距（三层，逐层都要改）

| 层 | 现状 | 需要的改动 |
|---|---|---|
| 计费 | `Fees` 只有单一方案 | 增加 `mode: :box` 分支，**不套 1900 L 下限** |
| 决策 | 工作台不展示费用；文档明确"不推荐最低运费" | 新增择优服务 + 页面展示 |
| 写入 | `ozon_supply_runner.rb:204` 硬编码 `"PALLET"` | 支持箱型 cargo |

### 5.2 择优规则

```
硬约束（先于费用）：
  - 点位只收箱（如 СЦ Ханты-Мансийск）→ box
  - 点位只收托（如 Софьино/Домодедово/Пушкино-1 РФЦ）→ pallet
  - ПВЗ/ППЗ → 只能 box
  - 箱数 > 30 且未启用运输货位 → 只能 pallet（官方箱数上限）

费用比较（无硬约束时）：
  cost_box    = ceil(商品总体积) × box_rate
  cost_pallet = max(ceil(商品总体积), 1900) × pallet_rate
  推荐 = min(cost_box, cost_pallet)
  同时输出平衡体积 = 1900 × pallet_rate / box_rate，供运营理解阈值
```

费率来源**复用现有表**：`RawOzon::CrossDockTariff#for_route(...)` + `#amount_for(...)`，无需新建数据源。快照缺失时按现有约定**不补 0**（沿用 `Fees` 的 `missing` 机制）。

### 5.3 新增服务 `PalletPacking::ShippingModeAdvisor`

```
输入：商品总体积、收货区、目的集群、点位类型、快照
输出：{ recommended: :box | :pallet,
        box: { cost:, rate: }, pallet: { cost:, rate: },
        break_even_volume_l:, blocked_by: nil | :point_type | :box_count_limit }
```

纯计算，不读写 DB（除传入的费率快照）。

工作台在当前清单上方展示送货方式识别，并将费率区、交货日期放在方式选择旁边。每次验算按同一清单比较两种方式：报价完整时推荐路线及点位费用最低者并展示价差；仅一种方式满足硬约束时可在费用未知的情况下推荐，并说明依据。两种方式均可用但报价不全时，只提示“可按箱送货”及补齐报价信息，不推断更便宜。

识别提示提供一键切换并重新验算，保留商品和箱数、清除旧托盘分配，支持撤销。清单或参数变化后立即清除旧建议，验算通过后才允许保存；模式不自动切换。当前所选方式验算失败时仍保留原错误，用户也可直接通过方式选择器改为箱送后重试。

### 5.4 平台写入扩展

货位写入结构由 Ozon Seller API 公开 OpenAPI schema 确认：

现有 payload（`ozon_supply_runner.rb:204`）：
```ruby
value: { type: "PALLET", items: [...] }
```

- `POST /v1/cargoes/create` 的 `ValueCargoType` 明确允许 `BOX`、`PALLET`；请求两种类型共用 `items: [{barcode, offer_id, quant, quantity}]`。
- 同一 schema 标注普通供货最多 30 箱或 40 托。当前实现不启用运输货位扩容。
- 本地调研中的 `CARGO_TYPE_PALLET` 不是此接口请求体所用枚举；外部请求必须使用 schema 中裸值 `PALLET` 或 `BOX`。

### 5.5 数据模型影响

- `ec_pallets` 语义是"托盘"，箱送方案下需要区分"货运单元"概念。两种选择：
  - A（推荐）：保留 `ec_pallets`，新增 `cargo_type` 字段区分 pallet/box；
  - B：新增独立表。成本更高。
- `ec_pallet_plans.calculation`（jsonb）已容纳托盘数与箱数，无需迁移。

### 5.6 测试

- `ShippingModeAdvisor` 单测：用**真实费率快照**断言平衡体积与推荐方向；
- 硬约束测试：ПВЗ 只能箱、只收托点位只能托；
- `Fees` 的 `mode: :box` 分支：断言**不套 1900 L 下限**；
- 回归：现有 `calculator_test.rb` 的 1900 L 断言（`:98`）必须保持。

### 5.7 验收标准

- 给定体积 800 L：推荐箱送，且 `cost_box < cost_pallet`；
- 给定体积 2,500 L：推荐打托；
- 只收托点位：强制打托，`blocked_by: :point_type`；
- 费率快照缺失：返回未知而非 0。

---

## 6. 实施顺序与依赖

```
阶段 1（尺寸分类修正）        ← 独立，可立即做，修正缺陷
   ↓ 提供正确的类别
阶段 2（补货量区间 + 填充）   ← 复用 Packing 的 @capacities
  ↓ 费用与货位类型进入决策
阶段 3（箱/托择优）           ← 复用 CrossDockTariff 与 cargo create schema
```

**关键依赖**：阶段 2 的"免费空间"论证依赖 1900 L 下限（已实现）；阶段 3 的费率依赖 `RawOzon::CrossDockTariff`（已有 1,376 条真实数据）。

三个阶段已在同一变更中实现，并按阶段依赖完成验证；本文件记录目标行为与实现口径。

## 7. 实现口径与未接入边界

### 7.1 "免费越库"的判定基准

采用**整批托盘数、路线计费体积及提货/点位处理费**判断。增补逐箱调用现有 `Packing`，任一预算上升时即停止；分拣、仓储费用的已知增量单独展示，不阻止使用已付运输空间。装托启发式不保证单调，因此不使用二分搜索，也不宣称全局最优。

### 7.2 箱送的 30 箱上限

普通箱型货位按公开接口上限实现为每单最多 30 箱；暂不支持运输货位及 200/1500 箱上限。工作台试算、保存和提交前均执行该约束。

### 7.3 尺寸分类以谁为准

沿用服务端 `Ec::SkuDimension` 的内包装尺寸/重量实时分类；客户端分类不能覆盖。尚无可靠的平台复测类别同步来源，本次不以存量分类字段覆盖实时结果。Ozon 最终准入与货位规则回读仍是平台侧权威校验。

### 7.4 其他已知未决事实（非阻塞，但影响后续）

- `platform_covered_units` 暂无写入路径，仍为 0；区间计算沿用现有库存/在途/计划数量输入。
- 普通箱送复用 Ozon FBO 的外箱校验与单箱几何数据，不新增第二套 profile；每箱单 SKU、单箱货重不超过 25 kg。
- 箱送不支持运输货位，不超过公开的 30 箱限制。

---

## 8. 影响面与风险

| 风险 | 等级 | 缓解 |
|---|---|---|
| 阶段 1 改变 `packing.rb` 混托行为 | 中 | 补测试；确认"非分拣与大件分开"是期望行为 |
| 阶段 1 迁移回填量大 | 低 | 照现有迁移模式；只读验证后执行 |
| 阶段 2 填充导致托盘数增加 | 中 | 第 1 层严格优先；每步重算几何并回退 |
| Ozon 货位/点位最终准入仍由平台决定 | 中 | 提交前本地校验，并保留平台规则回读；不执行盲目重试 |
| 阶段 3 费率快照过期 | 中 | 沿用 `Fees` 的 `missing` 机制，不补 0 |
| 三处阈值再次漂移 | 低 | 收敛到 `OZON_SIZE_LIMITS` 常量 |

---

## 9. 附录：本文引用的关键文件

**现有实现**
- `app/models/ec/sku_dimension.rb`（分类判定，`:42-53`）
- `app/services/ec/pallet_plans/{workbench_query,build,packing,save,availability}.rb`
- `app/services/pallet_packing/{rules,calculator,fees}.rb`
- `app/services/ec/ozon_warehouse_recommendation_query.rb`（缺口公式 `:238`）
- `app/services/ec/pallet_plans/ozon_supply_runner.rb`（平台写入 `:204`）
- `app/models/raw_ozon/cross_dock_tariff.rb`（箱/托双费率）
- `db/migrate/20261020013933_*`、`db/migrate/20261020031211_*`（阈值重复）

**官方口径来源**
- `ozon_wb_docs/ozon-docs/commissions-tariffs/commissions-tariffs-ozon/rashody-na-dop-uslugi.md`（1900 L、仓储费率）
- `ozon_wb_docs/ozon-docs/fbo/crossdoking/kross-doking.md`（箱/托限制、点位）
- `ozon_wb_docs/wildberries-ozon-pallet-rules-zh.md`（中文汇总）
- `ozon_wb_docs/ozon-crossdock-tariffs-2026-09-16.csv`（11,080 条费率）
- 在线：`/libra/kgt/fbo/postavka-kgt-fbo`、`/libra/fbo/.../k-kakoi-zone-otnositsya-tovar`、`/libra/work-with-goods/.../product-information/ovh`

**项目文档**
- `docs/pallet_calculator/README.md`、`docs/ozon_pallet_workbench_implementation_plan.md`、`docs/ozon_pallet_supply_sync.md`、`docs/20260718-Ozon-WB仓储发货规则知识库.md`

---

## 10. 验证说明

**本文已实际核对**：第 2 节全部代码结论均在 `main` 上逐条查证（含 `sku_dimension.rb:50`、`workbench_query.rb:99`、`packing.rb:41-43`、`ozon_supply_runner.rb:204`、`fees.rb:13`、`cross_dock_tariff.rb:23-25`、三处阈值重复）；第 1.5 节盈亏平衡由**项目库 1,376 条真实费率**实算，并用官方 CSV 11,080 条交叉验证；1.3/1.4 官方口径取自上述文件与页面。

**实现依据**：Ozon Seller API 的公开 OpenAPI schema `https://docs.ozon.ru/api/seller/en/swagger.json` 中，`POST /v1/cargoes/create` 的 `ValueCargoType` 明确枚举 `BOX`、`PALLET`，`v1CargoesCreateRequest` 说明每单最多 30 个箱或 40 个托；请求两类共用 `items` 结构。本地完整模拟链路覆盖 `BOX` 创建、数量/箱量守恒及 cargo ID 回填。没有对真实 Ozon 执行写入；平台实际准入由提交后的 Ozon 规则接口确认。
