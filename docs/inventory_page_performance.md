# 库存列表页性能优化

测量日期：2026-10-20。

## 修改范围与业务口径

- `Ec::InventoryPageStockQuery` 对全部筛选 SKU 一次计算库存账本，按 SKU 汇总在购批次和最新 FBO/FBW、在途库存。
- 同一请求的体积汇总和当前页行查询共用这批库存数据，减少逐 SKU 的完整库存概览查询。
- 继续复用 `Ec::Inventory::BookLedger` 及其 `compose`，保留订单硬关联、退货分配、状态优先级、过期未发货订单及库存计算规则。
- 在购量仍只包含 normal 类型的 draft/ordered/in_transit 批次，沿用有效实收数量公式；体积仍逐 SKU 忽略无效体积和非正贡献。
- 当前页的实物库存继续由原对账查询计算，传入同一批账本的实收数量。单行查询未传批量数据时继续使用原有完整概览。
- 周转筛选继续按用户日期的日终计算，当前库存继续按当前状态计算，分别保留各自的时间口径。
- 数据仅在请求内复用，每次刷新重新查询。

## 本地完整 HTML 请求对比

本地 development 数据库包含 238 个 SKU、23,802 笔订单。使用已有 manager 用户，业务时间固定为上海时区 2026-10-20 12:00；数据库事务设为只读，同时启用 `while_preventing_writes`。关闭 ActiveRecord query cache，统计排除 SCHEMA、TRANSACTION 和缓存命中的 SQL。

下表为完整 `GET /reports/inventory` 请求，包含筛选组件、顶部汇总、当前页销量和预测、实物库存、诊断标签、分页与布局渲染。

| 场景 | SQL 修改前 → 后 | 实例化记录修改前 → 后 | 最长 SQL 字节修改前 → 后 | 请求耗时修改前 → 后 |
| --- | ---: | ---: | ---: | ---: |
| 默认第一页 | 3,021 → 100 | 9,800 → 7,154 | 3,008 → 14,352 | 4.869 s → 1.403 s |
| `sku=QJD001`，5 个 SKU | 112 → 71 | 795 → 699 | 1,591 → 1,640 | 0.439 s → 0.434 s |
| `turnover_days_max=30` | 483 → 163 | 7,771 → 7,179 | 14,352 → 14,352 | 1.462 s → 1.054 s |

默认页 SQL 累计耗时从 2.876 s 降至 0.297 s。每组在独立 Rails 进程内顺序测量，完整请求前先执行全量基础行校验；未清空 PostgreSQL 或操作系统缓存。耗时为本地单次样本，不作为生产性能承诺。

另外对全部 238 个 SKU 的完整基础行进行服务级校验：SQL 从 3,669 降至 30，实例化从 9,075 降至 6,429，耗时从 4.196 s 降至 0.796 s。该统计不包含实物库存、预测及页面渲染。

最长 SQL 增长来自原账本使用 Rails preload 批量加载退货明细时的 return_id 条件。相关订单及 posting 查询仍使用 Relation 子查询；没有新增手工拼接订单号数组。对该退货明细 SQL 的只读执行计划检查约为 0.6 ms。

对默认页剩余耗时靠前的账本销量聚合、需逐单分配的订单明细及退货查询执行了只读 `EXPLAIN (ANALYZE, BUFFERS)`，分别约为 93、48、19 ms。订单商品使用 platform_sku_id 的 Bitmap 索引，订单、履约主键及退货 order_id 索引继续生效；全量小表的顺序扫描符合当前数据规模，本次没有新增索引。

## 一致性与回归

- 全部 238 个 SKU 的完整基础行字段逐项一致。
- 上述三个完整请求的行字段、实物库存、预测、诊断事件属性、体积汇总、总条数及表格/分页展示文本一致；比较时排除内部 `cache_updated_at` 时间。
- 回归覆盖正常采购与调整批次、各采购状态及有效数量、取消/过期订单和退货账本规则、FBO/FBW/在途与历史快照、完整实物库存结果等价。
- 批量从 1 个 SKU 增至 12 个 SKU（同一退货订单包含多个 SKU）时，未缓存 SQL 数量保持一致，且不查询列表无需展示的供货和移除明细；空 SKU 不发起查询。
- 真实数据集成测试验证 12 个 SKU 跨两页汇总、负库存贡献排除，以及修改第 2 页批次后刷新第 1 页立即反映新汇总。
- 相关 Rails 测试在临时独立 test 数据库执行：50 runs、444 assertions，全部通过。既有测试桩补充批量参数，采购批次测试补齐自动生成的操作记录清理。

验证命令（先初始化 rbenv，再使用独立的本地 `DATABASE_URL`）：

```sh
bin/rails test test/services/ec/inventory_page_stock_query_test.rb \
  test/services/ec/inventory_page_row_query_test.rb \
  test/controllers/inventory_volume_summary_cards_test.rb \
  test/services/ec/inventory_volume_summary_builder_test.rb \
  test/services/ec/inventory_report_row_metrics_builder_test.rb \
  test/services/ec/inventory_turnover_metrics_query_test.rb \
  test/services/ec/inventory_velocity_metrics_query_test.rb \
  test/services/ec/inventory/book_ledger_test.rb

bin/rails test test/controllers/reports_controller_test.rb \
  test/controllers/reports_inventory_health_test.rb -i /inventory_report/
```
