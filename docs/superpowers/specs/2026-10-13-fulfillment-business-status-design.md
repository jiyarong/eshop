# 发货单业务状态（Fulfillment Business Status）设计

日期：2026-10-13
状态：待评审

## 1. 目标

给 `ec_order_fulfillments` 新增两个与平台无关的状态字段，把 WB 和 Ozon 的订单／退货状态抹平：

- `business_status`（业务状态）：这单货走到发货链路的哪一步。
- `return_business_status`（退货业务状态）：这单货的退货流转走到哪一步。

两者相乘（业务状态 × 退货业务状态）完整描述一个发货单，物理盘库的 FBS 板块用这张交叉表代替现在的 27 个订单阶段，交叉表每个数字可以点开看对应订单。

非目标：

- 不改 `ec_orders.order_status` 的取值和现有消费者（约 35 个文件在读它）。
- 不迁移账面库存、销量、利润等其他报表，它们另行迁移。
- 不处理 FBO／FBW 的物理盘库，字段对所有履约方式计算，但本次只有 FBS 交叉表读取。
- 不处理无订单的 WB 残次退货（72 条），它们仍留在"平台移出与无订单残次"板块。

## 2. 验证结论（数据来自本地开发库，最新订单 2026-10-09）

| # | 结论 | 数据 |
|---|---|---|
| 1 | Ozon 订单状态与退货单状态相互独立，订单状态永远不会变成 `returned` | 已签收订单有退货：FBO 333、FBS 42；已取消订单有退货：FBO 1250、FBS 208 |
| 2 | WB 订单状态会被统计流水改写成 `returned`／`cancelled`，但 `returned` 不等于货回到卖家 | 131 个 `returned` 订单只有 18 个有卖家侧退货记录 |
| 3 | WB `returned` 里真正"卖出后被退回"的极少，多数是取货时取消或残次 | `canceled_by_client` 56、`defect` 21、`canceled` 3、`sold` 2、FBW 统计订单 45、状态卡在 `waiting` 4 |
| 4 | WB `cancelled` 混合了发出前和发出后取消 | 带退货记录的 522 个 FBS 取消单里，411 个已被卖家领回，41 个仍在回程 |
| 5 | WB 状态会卡住 | 29 个订单（2026-05 至 07）停在 `waiting/new`，没有统计订单，退货记录已 `completed` |
| 6 | 订单可对应多个发货单 | Ozon 289 个多 posting 订单，其中 31 个发货单状态互相冲突；`ec_orders.order_status` 现在是"最后导入者说了算" |
| 7 | Ozon 退货能精确挂到发货单 | 1890 条退货的 `posting_number` 100% 匹配订单下某个发货单 |
| 8 | 不存在部分退货 | 数量大于 1 的订单行只有 15 条（全是 Ozon），没有一条有退货；WB 数量恒为 1 |
| 9 | Ozon 有 36 条退货状态未映射，落成 `unknown` | `Cancelled` 14、`Approved` 6、`WriteOff` 6、`PotentiallyLost` 4、`ArrivedAtReturnPlace` 3、其余 3 |
| 10 | WB `waiting + complete` 现在被当作"待发运、不扣"，与 WB 文档和取消单离仓判断都不一致 | 文档：供货交接后进入 `complete`，即配送中；开发库 20 个 |

## 3. 取值

### 3.1 业务状态（6 个）

| 值 | 含义 | 在仓 |
|---|---|---|
| `awaiting_assembly` 待装配 | 新单，货在卖家仓，还没打包／没加入供货 | 是 |
| `awaiting_dispatch` 待发运 | 已备好，在卖家仓等待交接 | 是 |
| `in_delivery` 配送中 | 已离仓，买家未签收 | 否 |
| `delivered` 已签收 | 买家已收／已成交 | 否 |
| `cancelled` 已取消 | 订单取消 | 看退货轴 |
| `needs_review` 待核实 | 平台状态缺失或无法识别 | 是（沿用现有保守口径） |

### 3.2 退货业务状态（6 个）

| 值 | 含义 |
|---|---|
| `none` 无退货 | 没有退货记录，也没有应退证据 |
| `expected` 待退回 | 已发出后取消或拒收，平台尚未出退货记录（现 `cancelled_dispatched_return_pending`） |
| `at_platform_side` 在平台侧 | 买家申请、运往平台、在平台退货仓、WB 在途 |
| `returning_to_seller` 返回卖家途中 | 平台已发回卖家，或已在提货点等卖家领取 |
| `received_by_seller` 卖家已收 | 货已回到卖家仓 |
| `no_physical_return` 无实物回流 | 只退款，或退货被取消／驳回，或丢失、销毁 |

## 4. 映射规则

两个值都由一个纯函数（`Ec::FulfillmentBusinessStatus`）根据发货单的源状态、WB 统计证据和关联退货算出，不读写其他表。输入由 `Ec::FulfillmentBusinessStatus::Updater` 从数据库收集。

### 4.1 业务状态

按下列顺序，先命中先返回：

| 平台 | 条件 | 业务状态 |
|---|---|---|
| WB | 平台状态属于取消类：`canceled`、`canceled_by_client`、`declined_by_client`、`defect`、`canceled_by_carrier`；或卖家状态 `cancel`、`cancelled`、`cancel_carrier`；或发货单状态 `cancelled`；或统计证据为 `cancel` | 已取消 |
| WB | 统计证据为 `return` 或 `sale`，或发货单状态 `delivered`／`returned`，或平台状态 `sold`／`returned` | 已签收 |
| WB | `waiting` + `new` | 待装配 |
| WB | `waiting` + `confirm` | 待发运 |
| WB | `waiting` + `complete`，以及 `sorted`、`ready_for_pickup`、`postponed_delivery`、`accepted_by_carrier`、`sent_to_carrier` | 配送中 |
| WB | 其余（统计订单没有平台状态等） | 待核实 |
| Ozon | `cancelled`、`not_accepted`，或子状态 `posting_canceled` | 已取消 |
| Ozon | `delivered`，或子状态 `posting_received`、`posting_delivered` | 已签收 |
| Ozon | `awaiting_packaging` | 待装配 |
| Ozon | `awaiting_deliver`、`awaiting_delivery` | 待发运 |
| Ozon | `delivering`、`driver_pickup`、`sent_by_seller`，或子状态 `posting_transferred_to_courier_service`、`posting_in_carriage`、`posting_on_way_to_city`、`posting_in_pickup_point` | 配送中 |
| Ozon | 其余（`awaiting_registration`、`acceptance_in_progress`、`awaiting_approve`、`arbitration` 等） | 待核实 |

关键差别：

- WB 的取消类平台状态优先于 R 流水。`canceled_by_client + R 流水`（买家取货时取消）归"已取消"，不归"已签收"，退货轴会标出货在回来路上。
- **WB 统计证据优先于卡住的平台状态**：平台状态停在 `waiting/new`，但统计流水已有成交（S），归"已签收"。现有订单分布就是靠统计证据修正的（`wb_evidence_by_order_id`：同一订单取 `return` > `cancel` > `sale` > `order_only`，统计订单通过 `RawWb::StatsOrder` 的主来源链接和 `srid`／`g_number` 关联统计销售行，排除 `is_storno`）。新解析器必须读同一份证据，否则这类订单会被错误地算作仍在仓。
- Ozon `posting_returned_to_warehouse` 暂按"已取消"处理（见第 9 节）。

### 4.2 退货业务状态

取该发货单最新的一条有效退货（多条时取更新时间最晚者）。退货挂到发货单的顺序：`return_item.order_item_id` 对应的发货单；找不到再用 Ozon `posting_number`；再找不到用订单唯一的发货单。

| 来源 | 条件 | 退货业务状态 |
|---|---|---|
| Ozon | `ReceivedBySeller` | 卖家已收 |
| Ozon | `MovingToSeller`、`ReadyForSeller`、`ArrivedAtReturnPlace` | 返回卖家途中 |
| Ozon | `OnSellerApproval`、`WaitingShipment`、`Approved`、`MovingToOzon`、`ReturnedToOzon` | 在平台侧 |
| Ozon | `MoneyReturned`、`PartialCompensationReturned`、`Cancelled`、`CancelledDisputeNotOpen`、`Rejected`、`WriteOff`、`Utilized`、`PotentiallyLost` | 无实物回流 |
| WB 退货记录 | `completed_dt` 有值或状态 `Выдано` | 卖家已收 |
| WB 退货记录 | `ready_to_return_dt` 有值（`Готов к выдаче`、`Истек срок хранения на пвз`） | 返回卖家途中 |
| WB 退货记录 | 其余进行中（`В пути в пвз`、`Погружен в машину до СЦ/РЦ` 等） | 在平台侧 |
| WB 无退货记录 | 统计证据为 `return`，或发货单状态 `returned` | 在平台侧 |
| 任一平台 | 无有效退货，业务状态为已取消，且有离仓证据 | 待退回 |
| 任一平台 | 其余 | 无退货 |

离仓证据：WB 的 `supplier_status = complete`（以发货单源子状态或关联的 `RawWb::Order` 为准）；Ozon 的 `RawOzon::PostingFbs.delivering_date` 非空。

## 5. 物理盘库交叉表

只统计 `fulfillment_type = fbs` 的发货单，按订单行数量求和（订单行到 SKU 仍走 `ec_sku_products` 硬关联）。每个格子归入三类之一：

| | 无退货 | 待退回 | 在平台侧 | 返回卖家途中 | 卖家已收 | 无实物回流 |
|---|---|---|---|---|---|---|
| 待装配 | 未离仓 | 异常 | 异常 | 异常 | 异常 | 异常 |
| 待发运 | 未离仓 | 异常 | 异常 | 异常 | 异常 | 异常 |
| 配送中 | 已离仓 | 异常 | 已离仓（异常） | 异常 | 已回仓（异常） | 异常 |
| 已签收 | 已离仓 | 异常 | 已离仓 | 已离仓 | 已回仓 | 已离仓 |
| 已取消 | 未离仓 | 已离仓 | 已离仓 | 已离仓 | 已回仓 | 已离仓 |
| 待核实 | 未离仓 | 异常 | 异常 | 异常 | 异常 | 异常 |

规则只有一条：**货曾经离开卖家仓 ⇔ 存在任何退货记录（含待退回），或业务状态是配送中／已签收；"已取消且无退货"以及三种在仓业务状态下无退货的，从未离仓**。其中"卖家已收"的那一列额外标成"已回仓"，因为这些货会通过退货加回。

"异常"是逻辑上不该出现的组合，页面上单独标出，数量照常按上面的规则计入已离仓（有退货记录就证明货走过）。典型例子：卡在 `waiting/new` 但退货已完成的 WB 订单会落进"待装配 × 卖家已收"，它们现在会被算作"已离仓"再由退货加回，不再被重复加回一次。

### 公式

公式结构保持不变，只是"FBS 离仓件数"改为从交叉表取"已离仓"和"已回仓"格之和：

```
盘库应见库存 = 累计入库 + 物理盘库矫正
             − FBS 离仓件数（交叉表"已离仓"与"已回仓"格之和）
             − WB 送仓离仓 − Ozon 送仓离仓
             + 卖家已收退货
             + Ozon 移出已收
```

`fbs_departed_quantity`、`fbs_not_departed_quantity`、`fbs_order_quantity` 三个指标沿用原有含义：已离仓（含已回仓）件数、未离仓件数、FBS 订单总件数。因此重构前后每个 SKU 的全部汇总指标可以直接逐项对比。

### 与现有口径的差异（用 2026-10-13 的基线与试跑结果核对）

在开发库上用解析器草案试跑，236 个 SKU 里 20 个的盘库应见库存变化，合计 −48，全部可解释：

| 差异 | 影响 |
|---|---|
| WB `waiting + complete`（供货已交接、平台尚未分拣）由"待发运、不扣"改为"配送中、已离仓" | 9 个 SKU，合计 −20：CYQ95-BK、JJ005-4、KJ-208-SV、KJ-228-WT、LDD005、MPJ001-YL、QJD001-3、SLHL002-2、ZJ092 |
| 卡在 `waiting/new` 但退货已完成的 WB 订单，由"未离仓却被加回"改为"已离仓再加回" | 10 个 SKU，合计 −29：CYQ97-WT、JXZ-GREY-01、JZJJ-001、CYQ97-BK、CZY001、LDD001-BK、KJ-228-SV、KJ-207-GY、JZDJ-YS、JXZ-WHITE-02 |
| 多发货单的 Ozon 订单：订单级状态是已取消，但这一行商品属于已妥投的 FBO 发货单。旧逻辑按订单找 FBS 发货单把它算成已取消的 FBS，新逻辑按商品所属发货单 | 1 个 SKU，+1：KJ-226-GY（订单 22790） |

其余 216 个 SKU 的每一项汇总指标应与基线完全一致。实现完成后不在此表中的差异都是缺陷，需要逐个查清。

## 6. 存储与更新

- `ec_order_fulfillments` 新增 `business_status`、`return_business_status`（字符串，非空，默认 `needs_review` 和 `none`），并建 `(business_status, return_business_status)` 联合索引。
- `ec_orders` 新增同名汇总字段，仅供订单列表展示。多发货单订单的汇总：业务状态按"待核实 > 待装配 > 待发运 > 配送中 > 已签收 > 已取消"取第一个存在的；退货状态按"待退回 > 在平台侧 > 返回卖家途中 > 卖家已收 > 无实物回流 > 无退货"取第一个存在的。
- 三个更新入口都调用同一个解析器：
  1. `Ec::OrderImport::Ozon`、`Ec::OrderImport::Wb`（含 `repair_statuses`）：写发货单时同时写两个状态。
  2. `Ec::Returns::BaseNormalizer`：每条退货保存后，重算它挂的发货单。
  3. 一次性回填脚本：幂等，可重复执行。
- 页面 GET 请求保持只读，不触发重算。
- 提供一个只读一致性检查（落库值与现算值对比），用于发现漏掉的触发路径。

## 7. 页面

- `reports/_inventory_physical_reconciliation.html.erb` 的"FBS 订单流转"板块：27 行表格换成上面的交叉表，每个格子是链接。
- 点击格子，用现有的 `erp_modal` 弹窗框架弹出订单列表（与同一板块里的"物理盘库矫正"弹窗一致，`inventory.html.erb` 和 `inventory_detail.html.erb` 已经渲染了这个框架）。新增一个只读 GET，参数为 `sku_code`、`business_status`、`return_business_status`、分页。
- 列表列：平台／店铺、订单号、发货单号、下单时间（`display_time`）、业务状态、退货业务状态、平台原始状态（沿用现有 `source_status_label`）、数量。表格用 `table_viewport`，分页在表格上方。
- 所有展示文案走 I18n（`zh`、`en`、`ru`），不新增硬编码文案。
- 现有 27 个阶段文案和合成阶段逻辑在新页面上线后移除；`Ec::InventoryOrderSalesDistributionQuery` 的其他消费者不受影响，保留。

## 8. 测试

- 解析器：表驱动，覆盖 4.1 与 4.2 两张映射表的每一行，加上多退货取最新、WB 取消类优先于 R 流水、统计证据优先于卡住的 `waiting/new`、离仓证据有无的组合。
- 回填：幂等，多发货单订单，无订单的 WB 退货不报错。
- 交叉表查询：每个格子的数量，异常格子单列。
- 弹窗控制器：筛选参数白名单、分页、权限沿用盘库详情页。
- 公式回归：用 `script/physical_stocktake_baseline.rb` 对比重构前后每个 SKU 的全部汇总指标，差异只允许来自第 5 节列出的三项。基线文件为 `docs/superpowers/baselines/2026-10-13-physical-stocktake-baseline.json`。
- 注意：`test/test_helper.rb` 里 `use_transactional_tests = false`，测试需用唯一 SKU 并自行清理数据。

## 9. 风险与待定项

| # | 事项 |
|---|---|
| 1 | 落库值可能因漏掉触发路径而过期，靠回填脚本和一致性检查兜底。 |
| 2 | Ozon `Cancelled`／`Rejected`／`CancelledDisputeNotOpen`（共 16 条）暂归"无实物回流"。对已取消的发货单这意味着"不算货已回来"，上线前需用线上数据抽查。 |
| 3 | Ozon `posting_returned_to_warehouse`（货被退回平台仓）开发库没有 FBS 样本，实现时按"已取消"处理并带测试，上线前用线上数据确认。 |
| 4 | WB "有 R 流水但无退货记录"归"在平台侧"是推断：113／131 的 `returned` 订单没有卖家侧退货记录，支持"货留在 WB"，但没有 WB 官方文档佐证。 |
| 5 | FBO／FBW 的两个状态值也会被计算，语义是"平台仓侧的同一阶段"，本次不被任何页面消费，后续迁移时再复核。 |
| 6 | 本文数据来自开发库的线上备份，不是实时线上；落地前需在线上做一次只读校验。 |

## 10. 后续

1. 迁移账面库存台账：`OrderItem.deductible_from_book_inventory` 改读新字段，可顺带解决 `2026-10-12-book-inventory-ledger-design.md` 第 2 节列出的第 2、3、4 项。
2. 迁移其余读 `order_status` 的报表，最终下线 `ec_orders.order_status` 的业务用途。
3. FBO／FBW 的物理盘库。
