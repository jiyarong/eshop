# 账目库存（Book Inventory Ledger）口径重构设计

日期：2026-10-12
状态：待评审

## 1. 目标

账目库存回答一个问题：**我名下一共有多少货，其中现在能卖多少（我自己的加上平台的）**。

它不负责回答货此刻在哪个仓库、有没有签收、送仓单到哪一步，这些是物理盘库（`Ec::InventoryPhysicalReconciliationQuery`）的职责。

非目标：

- 不改物理盘库的公式和页面。
- 不新建库存流水表（评估过，暂不需要）。
- 不回填历史快照（见第 9 节）。

## 2. 现状和问题

当前有**两套**账面库存实现，口径靠两个 scope 手工保持一致：

| 实现 | 用途 |
|---|---|
| `Ec::SkuInventoryOverview` | 实时：库存列表、抽屉、AI 上下文、导出 |
| `Ec::InventoryTurnoverMetricsQuery`（被 `Ec::InventorySnapshot` 调用） | 历史：每日快照、趋势、周转 |

两者共用 `OrderItem.deductible_from_book_inventory` 和 `ReturnItem.restockable_for_book_inventory`。

2026-10-12 线上查到的问题（全库、件数）：

| # | 问题 | 方向 | 件数 |
|---|---|---|---|
| 1 | WB `waiting/new` 订单超过 90 天仍当销量扣 | 偏低 | 260 |
| 2 | WB 状态 `returned` 的 FBS 订单仍被扣，且无可回库的退货记录 | 偏低 | 80 |
| 3 | Ozon 订单级状态与配送单状态不一致：已取消的配送单被当妥投 | 偏低 | 15 |
| 4 | Ozon 订单级状态与配送单状态不一致：已妥投的配送单被当取消 | 偏高 | 20 |
| 5 | WB FBW 统计订单（2026-04 至 05、08 月）从未转成订单，其中有成交 | 偏高 | 38 |
| 6 | 订单商品 ID 没绑到已有 SKU | 偏高 | 21 |
| 7 | 退货可回库只认 `ReturnedToOzon`、`ReceivedBySeller`，状态跳变时账面抖动 | 波动 | 2 |

此外，`available_stock`（FBS 库存 = 账面 − 平台预留）本质是自有仓位置，属于物理层面的推算。

## 3. 定义

对每个 SKU、每个时点 `as_of`：

| 名称 | 定义 |
|---|---|
| 总量 `ledger_total` | 入库（正常批次 + 调整批次，不含物理盘库矫正）− 净销量 |
| 平台可售 `platform_sellable` | 最新库存快照中 `fbo`、`fbw` 之和 |
| 平台待上架 `platform_inbound` | 最新库存快照中 `inbound` |
| 平台侧 `platform_side` | 平台可售 + 平台待上架 |
| 自有侧 `own_side` | 总量 − 平台侧（推算值，可为负，为负时标记数据异常） |
| 在途退货 `return_in_transit` | 已冲销、货还在回来路上的件数（见第 4.4 节） |
| 平台退货仓 `return_at_platform` | 已冲销、货在平台退货仓的件数 |
| 不可售 `unsellable` | 已冲销、按状态判定为不可再售的件数（见第 4.5 节） |
| 可售 `sellable` | 平台可售 + 自有侧 − 在途退货 − 平台退货仓 − 不可售 |
| 未归属 `unattributed` | 订单商品 ID 无法匹配任何 SKU 的已售件数，不进入任何 SKU 的数字，只在总览里列出 |

主数字是 `ledger_total`；`sellable` 和上面各项是拆分。在途退货、平台退货仓、不可售只做解释，不参与总量的加减。

## 4. 规则

### 4.1 订单归属

保持硬关联：`ec_sku_products.sku_code` 加 `store_id`、`platform`、`platform_sku_id`（Ozon）或 `product_id`（WB）匹配。不使用 `ec_order_items.sku_code`，不使用 `offer_id` 参与统计。

### 4.2 净销量

一个订单项计入净销量，当且仅当：

1. 能归属到该 SKU；
2. 订单项所属**配送单（履约单）**状态不是已取消。Ozon 以订单项关联的履约单为准，不用订单级状态；
3. 没有被冲销（见 4.3）；
4. 不是"待确认订单"（见 4.6）。

所有履约类型（FBS、FBO、FBW）一视同仁，延续 2026-06-30 设计的"WB 非取消订单全部计入"。

### 4.3 冲销

销售被冲销时，该订单项不计入净销量，不看货在哪里。冲销的触发：

| 平台 | 触发 |
|---|---|
| WB | 订单状态为 `returned`；或原始状态为取消类（`canceled_by_client`、`declined_by_client`、`defect`、`canceled`） |
| Ozon | 配送单已取消；或关联的退货单状态属于下表"冲销"类 |

Ozon 退货状态：

| `source_status` | 冲销 | 货的位置归类 |
|---|---|---|
| `OnSellerApproval`、`WaitingShipment`、`Approved` | 否（退货未确认） | — |
| `MovingToOzon` | 是 | 在途退货 |
| `ReturnedToOzon` | 是 | 平台退货仓 |
| `MovingToSeller`、`ReadyForSeller` | 是 | 在途退货 |
| `ReceivedBySeller` | 是 | 自有侧 |
| `MoneyReturned`、`PartialCompensationReturned` | 否（仅退款，货不一定回来） | — |
| `Cancelled`、`CancelledDisputeNotOpen`、`Rejected` | 否 | — |

WB 退货表：状态为 `Выдано` 的归自有侧，其余在回程中的归在途退货。无订单号的 WB 退货，只要能通过 `nm_id` 归属到该 SKU，就按"自有侧/在途退货"计入解释项，不影响总量。

### 4.4 在途退货

已冲销，且满足下面任一条、但还没有卖家签收的退货：

- Ozon：关联退货状态为 `MovingToOzon`、`MovingToSeller`、`ReadyForSeller`；或配送单已交付配送（`delivering_date` 有值）后取消且还没有任何退货记录；
- WB：订单已 `complete`（交付配送）后取消，退货表无 `Выдано`。

### 4.5 不可售（按状态自动归类）

已冲销订单项，满足下面任一条记为不可售：

| 平台 | 条件 |
|---|---|
| Ozon | 退货原因属于：商品不工作 / 缺陷、商品损坏但包装完好、包装和商品都损坏、商品伪造、使用中损坏、配件不全 |
| WB | 退货类型为"Возврат брака"；或订单原始状态为 `defect` |

其余冲销默认可售。不可售的件数仍在总量里（货属于你），只是不进 `sellable`。

### 4.6 待确认订单

状态为 `pending`、`processing` 且下单超过 **45 天**的订单项，不计入净销量，记入 `stale_open_orders`，供总览展示。同时修复同步：对未终态订单不再受 90 天回看期限制。

### 4.7 订单完整性

- WB 统计订单要全部转成订单（FBW 订单历史缺口一次性补转）。
- 新增完整性检查：原始订单没有对应订单、配送单没有履约单、数量不一致，任何一项非零就报警。
- 无法归属的订单进入 `unattributed`，不静默丢弃。

## 5. 与物理盘库的边界

| | 账目库存 | 物理盘库 |
|---|---|---|
| 回答 | 名下总量、可售 | 仓库里现在有多少 |
| 订单取消 | 冲销，货权不变 | 已发出的要扣，退货签收再加回 |
| 送仓单 | 不使用 | 使用 |
| 平台库存快照 | 使用 | 不使用 |
| 退货 | 状态确认即冲销 | 卖家签收才加回 |

两者共享的只有"订单是否已发出"的归类函数，放在同一个工具类里，避免各写各的。

对账恒等式（用于检查数据质量，不用于计算）：

`自有侧 − 物理盘库期望值 ≈ 在途退货 + 平台退货仓 + 不可售`

## 6. 对外输出

`Ec::SkuInventoryOverview#call[:summary]` 新增：

`ledger_total`、`platform_sellable`、`platform_inbound`、`platform_side`、`own_side`、`return_in_transit`、`return_at_platform`、`unsellable`、`sellable`、`unattributed`、`stale_open_orders`。

旧字段映射（保持名字，不破坏使用方）：

| 旧字段 | 新来源 | 备注 |
|---|---|---|
| `book_stock` | `ledger_total` | 数值会变化 |
| `available_stock` | `own_side` | 页面文案改为"自有侧（推算）" |
| `platform_stock` | `platform_sellable` | |
| `sales_quantity` | 净销量 | |
| `return_quantity` | 冲销件数 | |
| `supply_quantity` | 保留在 store_rows，标记为仅供参考 | 2026-06-30 设计已让其不参与计算 |

## 7. 实现结构

新增 `Ec::Inventory::BookLedger`，签名 `call(sku_codes:, as_of:)`，所有规则只在这里实现一次。

| 使用方 | 改动 |
|---|---|
| `Ec::SkuInventoryOverview` | 实时部分委托给 `BookLedger`（`as_of` 为当前） |
| `Ec::InventoryTurnoverMetricsQuery` | `book_stock` 委托给 `BookLedger`（`as_of` 为快照日） |
| `Ec::InventorySnapshot` | 不变，改由上面两者间接受益 |
| `OrderItem.deductible_from_book_inventory`、`ReturnItem.restockable_for_book_inventory` | 迁移到 `BookLedger` 后删除 |
| 页面、AI 上下文、Google Sheets 导出 | 先沿用旧字段名，新字段按需逐步接入 |

## 8. 上线步骤

1. **影子计算**：`BookLedger` 与旧公式同时计算，只输出差异报告，不改页面。
2. **验证**：差异必须能由第 2 节的 7 项问题解释；重点核对 `ReturnedToOzon` 的货是否已包含在 Ozon FBO 库存快照里（避免平台退货仓与平台可售重复扣）。
3. **补数据**：补转 WB FBW 统计订单、绑定 21 件未归属商品。
4. **切换**：旧字段改读 `BookLedger`，页面文案更新。
5. **清理**：删除旧 scope 和第二套实现。

## 9. 历史快照

`ec_snapshots` 里已存的每日库存快照不回填。趋势页在口径变更日加一条标注"账面口径调整"。变更日取切换当天，记为常量 `LEDGER_RULES_EFFECTIVE_ON`。

## 10. 测试

- `BookLedger` 单元测试：每条规则（冲销、待确认、配送单状态、不可售、未归属）各自一组用例，覆盖 WB 与 Ozon。
- 回归：旧字段在无新规则触发的数据上，新旧结果一致。
- 一致性：同一 SKU 的实时结果与同日快照结果一致。
- 对账：恒等式在测试数据上成立。

## 11. 已确认的决定

| 决定 | 内容 |
|---|---|
| 主数字 | 总量，可售作为拆分 |
| 待确认订单阈值 | 45 天 |
| 不可售 | 按状态自动归类 |
| 历史快照 | 不回填，只标注口径变更日 |

## 12. 待确认

1. `MoneyReturned`、`PartialCompensationReturned` 只退款、货不一定回来，设计里按"不冲销"处理，是否同意。
2. 不可售的原因清单（4.5 节）是否需要增减，例如 WB 的"неверного вложения"（错发）暂归为可售。
3. `ReturnedToOzon` 的货是否已包含在 FBO 库存快照中，需要在影子阶段用数据确认。
