# 物理盘库基线（重构前）

记录时间：2026-10-13
数据文件：[2026-10-13-physical-stocktake-baseline.json](2026-10-13-physical-stocktake-baseline.json)
用途：发货单业务状态重构（见 `docs/superpowers/specs/2026-10-13-fulfillment-business-status-design.md`）完成后，逐 SKU 对比盘库数字，核对差异。

## 记录范围

| 项 | 值 |
|---|---|
| 数据库 | `ecommerce_manage_development`（线上备份导入，最新订单 2026-10-09 09:00 UTC） |
| 代码版本 | `76e2f2862469374990cefc530d0e95edb06a7021`（工作区有 98 个未提交改动，未包含在该提交里） |
| SKU 数 | 236（0 个出错） |
| `ec_orders` | 22485 |
| `ec_order_fulfillments` | 22911 |
| `ec_returns` | 2534 |
| 稳定性 | 重新捕获一次，236 个 SKU 全部指标逐项一致 |

每个 SKU 记录：`Ec::InventoryPhysicalReconciliationQuery` 的全部汇总指标、FBS 订单行（平台、店铺、阶段、退货状态、平台原始状态、数量、是否扣减），以及送仓、退货、移出的行数。

## 全库合计（236 个 SKU 求和）

| 指标 | 数值 |
|---|---|
| 盘库应见库存 `expected_physical_stock` | 14450 |
| 累计已入库 `received_quantity` | 38863 |
| 物理盘库矫正 `physical_stocktake_adjustment_quantity` | 0 |
| FBS 确认离仓 `fbs_departed_quantity` | 10043 |
| FBS 仍在仓 `fbs_not_departed_quantity` | 684 |
| FBS 订单总量 `fbs_order_quantity` | 10727 |
| 送平台仓确认离仓 `platform_supply_departed_quantity` | 15567 |
| 　其中 WB | 3015 |
| 　其中 Ozon | 12552 |
| WB 送仓待核销 `wb_supply_reconciliation_quantity` | 15 |
| 待送平台仓 `pending_supply_quantity` | 408 |
| 卖家已收退货 `seller_received_return_quantity` | 544 |
| Ozon 移出已收 `ozon_seller_received_removal_quantity` | 653 |
| 移出待回仓 `removal_to_seller_quantity` | 39 |

139 个 SKU 的盘库应见库存非零，其中 13 个为负数。

## 如何对比

重构完成后：

```bash
bin/rails runner script/physical_stocktake_baseline.rb capture tmp/physical_stocktake_after.json
bin/rails runner script/physical_stocktake_baseline.rb compare docs/superpowers/baselines/2026-10-13-physical-stocktake-baseline.json tmp/physical_stocktake_after.json
```

对比前提：本地库不能重新导入线上备份，否则订单和退货条数会变，脚本会打印警告。

## 预期差异（重构前在开发库上用解析器草案试跑得到）

236 个 SKU 里 20 个的盘库应见库存变化，合计 −48，其余 216 个 SKU 的所有指标应与本文件一致。

| 原因 | SKU 与变化 |
|---|---|
| WB `waiting + complete` 由"待发运、不扣"改为"配送中、已离仓" | JJ005-4 −6、ZJ092 −4、SLHL002-2 −2、QJD001-3 −2、MPJ001-YL −2、LDD005 −1、KJ-228-WT −1、KJ-208-SV −1、CYQ95-BK −1（合计 −20） |
| 卡在 `waiting/new` 但退货已完成的 WB 订单，由"未离仓却被加回"改为"已离仓再加回" | CYQ97-WT −11、JXZ-GREY-01 −4、JZJJ-001 −4、CYQ97-BK −3、CZY001 −2、LDD001-BK −1、KJ-228-SV −1、KJ-207-GY −1、JZDJ-YS −1、JXZ-WHITE-02 −1（合计 −29） |
| 多发货单 Ozon 订单：订单级状态已取消，但该商品行属于已妥投的 FBO 发货单，旧逻辑按订单找 FBS 发货单把它算成已取消的 FBS | KJ-226-GY +1（订单 22790） |

上面的"CYQ97-WT −11"等是 SKU 级净变化；同一个 SKU 可能同时落在两类原因里，对比时以脚本输出的每 SKU 差异为准，逐个核对原因。
