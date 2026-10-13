# 物理盘库对比（重构后）

记录时间：2026-10-13
基线：[2026-10-13-physical-stocktake-baseline.md](2026-10-13-physical-stocktake-baseline.md)
重构后数据文件：`tmp/physical_stocktake_after.json`（未入库，可按下方命令重新生成）

## 记录范围

| 项 | 值 |
|---|---|
| 数据库 | `ecommerce_manage_development`（与基线同一份数据，最新订单 2026-10-09 09:00 UTC） |
| 代码版本 | `1f2b1ac5f62f33c075f1192af3b206c2b4518b7f`（工作区无未提交改动） |
| SKU 数 | 236（0 个出错） |
| `ec_orders` / `ec_order_fulfillments` / `ec_returns` | 22485 / 22911 / 2534（与基线一致） |
| 落库状态 | `script/backfill_fulfillment_business_status.rb --dry-run` 输出 `checked=22911 changed=0 dry_run=true` |

## 对比命令

```bash
bin/rails runner script/backfill_fulfillment_business_status.rb --dry-run
bin/rails runner script/physical_stocktake_baseline.rb capture tmp/physical_stocktake_after.json
bin/rails runner script/physical_stocktake_baseline.rb compare docs/superpowers/baselines/2026-10-13-physical-stocktake-baseline.json tmp/physical_stocktake_after.json
```

没有订单／退货条数不一致的警告，最后一行：

```
21 of 236 skus differ
```

送仓、退货、移出的行数在 236 个 SKU 上全部与基线一致。

## 差异 SKU

21 个 SKU 有差异，盘库应见库存合计 −48，与基线文档的预期一致；其中 20 个的盘库应见库存变化，JJ005-5 只有 FBS 未离仓件数和订单总量变化。

| SKU | 盘库应见库存 | FBS 指标变化 | 原因 |
|---|---|---|---|
| JJ005-4 | 0 → −6（−6） | 离仓 72 → 78，未离仓 11 → 5 | WB `waiting + complete` |
| ZJ092 | 1 → −3（−4） | 离仓 156 → 160，未离仓 9 → 5 | WB `waiting + complete` |
| SLHL002-2 | 10 → 8（−2） | 离仓 108 → 110，未离仓 15 → 13 | WB `waiting + complete` |
| QJD001-3 | 0 → −2（−2） | 离仓 355 → 357，未离仓 11 → 9 | WB `waiting + complete` |
| MPJ001-YL | −1 → −3（−2） | 离仓 49 → 51，未离仓 10 → 8 | WB `waiting + complete` |
| LDD005 | −3 → −4（−1） | 离仓 133 → 134，未离仓 5 → 4 | WB `waiting + complete` |
| KJ-228-WT | −18 → −19（−1） | 离仓 49 → 50，未离仓 16 → 15 | WB `waiting + complete` |
| KJ-208-SV | 77 → 76（−1） | 离仓 8 → 9，未离仓 1 → 0 | WB `waiting + complete` |
| CYQ95-BK | 161 → 160（−1） | 离仓 89 → 90，未离仓 8 → 7 | WB `waiting + complete` |
| CYQ97-WT | 903 → 892（−11） | 离仓 804 → 815，未离仓 47 → 36 | 卡在 `waiting/new` 且退货卖家已收 |
| JXZ-GREY-01 | −15 → −19（−4） | 离仓 159 → 163，未离仓 25 → 21 | 卡在 `waiting/new` 且退货卖家已收 |
| JZJJ-001 | 76 → 72（−4） | 离仓 218 → 222，未离仓 18 → 14 | 卡在 `waiting/new` 且退货卖家已收 |
| CYQ97-BK | 216 → 213（−3） | 离仓 609 → 612，未离仓 25 → 22 | 卡在 `waiting/new` 且退货卖家已收 |
| CZY001 | 300 → 298（−2） | 离仓 333 → 335，未离仓 6 → 4 | 卡在 `waiting/new` 且退货卖家已收 |
| LDD001-BK | 298 → 297（−1） | 离仓 112 → 113，未离仓 11 → 10 | 卡在 `waiting/new` 且退货卖家已收 |
| KJ-228-SV | −28 → −29（−1） | 离仓 103 → 104，未离仓 2 → 1 | 卡在 `waiting/new` 且退货卖家已收 |
| KJ-207-GY | 113 → 112（−1） | 离仓 43 → 44，未离仓 4 → 3 | 卡在 `waiting/new` 且退货卖家已收 |
| JZDJ-YS | −50 → −51（−1） | 离仓 236 → 237，未离仓 12 → 11 | 卡在 `waiting/new` 且退货卖家已收 |
| JXZ-WHITE-02 | 180 → 179（−1） | 离仓 79 → 80，未离仓 7 → 6 | 卡在 `waiting/new` 且退货卖家已收 |
| KJ-226-GY | −2 → −1（+1） | 离仓 26 → 25，订单总量 31 → 30 | 多发货单 Ozon 订单 22790，商品行属于已妥投的 FBO 发货单 |
| JJ005-5 | 9 → 9（0） | 未离仓 16 → 12，订单总量 191 → 187 | 多发货单 Ozon 订单 24570，4 件商品行属于已取消的 FBO 发货单（计划外，见下文） |

核对方法：

- WB `waiting + complete`：按商品所属 FBS 发货单查 `source_status = waiting`、`source_substatus = complete` 的 WB 商品行，9 个 SKU 的件数分别为 6、4、2、2、2、1、1、1、1，全部落在"配送中 × 无退货"（已离仓），与每个 SKU 的变化逐一相等；基线里同样的件数是"待交接、不扣"的行（例如 ZJ092 基线 `handover_pending / waiting / complete` 4 件不扣，重构后"配送中 × 无退货" 26 件 = Ozon 1 + 4 + WB 6 + 11 + 这 4 件）。
- 卡在 `waiting/new`：查业务状态为在仓（待装配／待发运／待核实）且退货业务状态不是"无退货"的 WB 商品行，只有上表 10 个 SKU，全部是 `waiting / new` → "待装配 × 卖家已收"（已回仓），件数分别为 11、4、4、3、2、1、1、1、1、1，与每个 SKU 的变化逐一相等；卖家已收退货 `seller_received_return_quantity` 不变，因此这些件数从"未离仓却被加回"变成"已离仓再加回"。例如 CYQ97-WT 基线 `waiting / new` 不扣的行 23 + 5 = 28 件，重构后"待装配 × 无退货" 17 件 + "待装配 × 卖家已收" 11 件 = 28 件。
- 两类都覆盖到的件数之外，没有其他 SKU 出现在这两个查询里。

## 多发货单订单的归属

旧查询处理已取消订单时，用 `item.order.fulfillments.find { fbs }` 按订单找 FBS 发货单，订单里只要有一个 FBS 发货单，整单所有商品行都按这个 FBS 发货单计入 FBS；新查询按商品行自己的 `fulfillment_id` 归属。全库查询"订单已取消、订单有 FBS 发货单、但商品行自己的发货单不是 FBS"的商品行，只有下面 5 行：

| SKU | 订单 | 商品行 | 数量 | 商品行所属发货单 | 订单里的 FBS 发货单 | 旧归类 | 新归类 |
|---|---|---|---|---|---|---|---|
| KJ-226-GY | 22790（Ozon，已取消） | 3395904 | 1 | 23034 FBO `23135164-0463-2`，`delivered / posting_received`，已签收 | 23036 `23135164-0463-1`，`cancelled / posting_canceled`，`delivering_date` 2026-09-15，退货 1891 `at_platform` | 已取消、已离仓待退回，扣减 | 不属于 FBS |
| JJ005-5 | 24570（Ozon，已取消） | 3397732 | 1 | 24862 FBO `0153225266-0111-3`，`cancelled / posting_canceled` | 24868 `0153225266-0111-1`，`cancelled / posting_canceled`，`delivering_date` 为空，无退货 | 已取消、未离仓，不扣 | 不属于 FBS |
| JJ005-5 | 24570 | 3397733 | 1 | 24863 FBO `0153225266-0111-5`，同上 | 同上 | 同上 | 同上 |
| JJ005-5 | 24570 | 3397734 | 1 | 24864 FBO `0153225266-0111-7`，同上 | 同上 | 同上 | 同上 |
| JJ005-5 | 24570 | 3397735 | 1 | 24865 FBO `0153225266-0111-9`，同上 | 同上 | 同上 | 同上 |

- KJ-226-GY：这件货由 FBO 仓发出并已妥投，从未离开卖家仓，旧逻辑把它算作 FBS 离仓并扣减，新逻辑不再扣，盘库应见库存 +1，与预期一致。同一订单里属于 FBS 发货单 23036 的商品行 3395906 是 KJ-226-SV，新旧都按"已取消 × 在平台侧"扣减，KJ-226-SV 无差异。
- JJ005-5：订单 24570 有 5 个发货单，FBS 发货单 24868 上的商品行 3397738 共 3 件，新旧都算"已取消、未离仓"；另外 4 件属于 4 个已取消的 FBO 发货单，旧逻辑把它们一起算进 FBS"已取消、未离仓"（基线 Ozon `cancelled_before_dispatch` 7 件），新逻辑只算 3 件（重构后"已取消 × 无退货" 4 件 = Ozon 3 + WB `declined_by_client / new` 1）。这 4 件旧逻辑本来就不扣，所以盘库应见库存不变，只有未离仓件数和 FBS 订单总量各 −4。

## 重构后全库合计（236 个 SKU 求和）

| 指标 | 数值 | 相对基线 |
|---|---|---|
| 盘库应见库存 `expected_physical_stock` | 14402 | −48 |
| 累计已入库 `received_quantity` | 38863 | 0 |
| 物理盘库矫正 `physical_stocktake_adjustment_quantity` | 0 | 0 |
| FBS 确认离仓 `fbs_departed_quantity` | 10091 | +48 |
| FBS 仍在仓 `fbs_not_departed_quantity` | 631 | −53 |
| FBS 订单总量 `fbs_order_quantity` | 10722 | −5 |
| 送平台仓确认离仓 `platform_supply_departed_quantity` | 15567 | 0 |
| 　其中 WB | 3015 | 0 |
| 　其中 Ozon | 12552 | 0 |
| WB 送仓待核销 `wb_supply_reconciliation_quantity` | 15 | 0 |
| 待送平台仓 `pending_supply_quantity` | 408 | 0 |
| 卖家已收退货 `seller_received_return_quantity` | 544 | 0 |
| Ozon 移出已收 `ozon_seller_received_removal_quantity` | 653 | 0 |
| 移出待回仓 `removal_to_seller_quantity` | 39 | 0 |

FBS 合计变化拆分：离仓 +48 = 20 + 29 − 1；未离仓 −53 = −20 − 29 − 4；订单总量 −5 = −1（KJ-226-GY）− 4（JJ005-5）。

141 个 SKU 的盘库应见库存非零，其中 16 个为负数（基线 139 个、13 个负数）。

## 计划外的差异

JJ005-5（未离仓 −4、FBS 订单总量 −4，盘库应见库存不变）。原因与 KJ-226-GY 相同：已取消的多发货单 Ozon 订单 24570 里，4 件商品行属于 FBO 发货单，旧逻辑按订单找 FBS 发货单把它们算成 FBS，新逻辑按商品所属发货单归属，这是预期的口径修正；计划里漏列是因为预期差异表只按盘库应见库存的变化列出 SKU，而这 4 件落在不扣减的"未离仓"里。结论：不是缺陷，无需改代码。

## 已退货状态上线后复核

业务状态新增第 7 个值 `returned`（已退货）：已签收且有成立退货的发货单由"已签收"改判为"已退货"，口径见设计文档 4.1.1。只改归类名称，不应改变任何盘库数量，因此用同一份基线重新比较。

回填（开发库，`ecommerce_manage_development`，只写两个状态列）：

| 步骤 | 输出 |
|---|---|
| 回填前试跑 `--dry-run` | `checked=22911 changed=437 dry_run=true`（样本全部是 `delivered → returned`，退货轴不变） |
| 实际回填 | `checked=22911 changed=437 dry_run=false` |
| 回填后再次试跑 `--dry-run` | `checked=22911 changed=0 dry_run=true`（幂等） |

`fulfillment_type = 'fbs'` 的发货单分布（回填后，合计 10952）：

| 业务状态 | 退货业务状态 | 发货单数 |
|---|---|---|
| 待装配 | 无退货 | 192 |
| 待装配 | 卖家已收（异常） | 29 |
| 待发运 | 无退货 | 1 |
| 配送中 | 无退货 | 794 |
| 配送中 | 在平台侧（异常） | 2 |
| 已签收 | 无退货 | 7922 |
| 已签收 | 无实物回流 | 1 |
| 已退货 | 在平台侧 | 25 |
| 已退货 | 返回卖家途中 | 6 |
| 已退货 | 卖家已收 | 16 |
| 已取消 | 无退货 | 441 |
| 已取消 | 待退回 | 707 |
| 已取消 | 在平台侧 | 283 |
| 已取消 | 返回卖家途中 | 74 |
| 已取消 | 卖家已收 | 454 |
| 已取消 | 无实物回流 | 1 |
| 待核实 | 无退货 | 4 |

"已签收"不再有在平台侧、返回卖家途中、卖家已收的组合；"已签收 × 无实物回流"只剩 1 条（只有作废退货）。

对比命令与结果：

```bash
bin/rails runner script/physical_stocktake_baseline.rb capture tmp/physical_stocktake_returned.json
bin/rails runner script/physical_stocktake_baseline.rb compare docs/superpowers/baselines/2026-10-13-physical-stocktake-baseline.json tmp/physical_stocktake_returned.json
```

```
21 of 236 skus differ
```

差异的 21 个 SKU、每个 SKU 的指标变化与上文"差异 SKU"表逐项相同，盘库应见库存合计仍为 −48，没有新增差异。
