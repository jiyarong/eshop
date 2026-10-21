# 补货方案 → Ozon 供货单 → 箱/托货位

工作台先试算并保存计划，再进入 `/reports/pallet_plans/:id` 计划详情页点击“创建交货申请”。申请使用该计划已保存的店铺、集群、清单与逐托分配，支持直送及交货点 Cross-dock。发起前校验计划版本、可编辑状态、权限、库存与装托约束，排除该计划自身库存占用；发起过程不重建计划、清单或托盘。已有有效提交会被复用，已终止的提交可在详情页重新发起。

计算器填写箱数与未填写箱数时生成的装托推荐均可使用；保存前会再次检查包装、单件尺寸类别、Listing 唯一性、SKU 权限、库存及每托分配，推荐数量超过库存时需先调整箱数。

## 人工操作

1. 工作台试算通过后保存计划，进入计划详情页，选择直送 / Cross-dock 方式。Cross-dock 需要选择该店铺接口返回的交货点。计算器已有入口仍在 Ozon FBO 结果处选择店铺、目标集群及供货方式。
2. 计划详情页点击“创建交货申请”，计算器点击“保存方案并查询可供货仓库”。本地保存提交记录（计算器同时保存独立计划），后台创建 Ozon 草稿；此时不创建正式供货单、不新增库存占用。
3. 在计划详情选择平台计算的完整可供货仓库，查询时段。预约时段展示平台返回的仓库当地时间及其时区，提交原始 `from_in_timezone/to_in_timezone`，不按用户时区二次换算。
4. 选择时段，点击“创建供货单并同步托盘”。重新检查库存，确认本地占用，后台建单并写入每托明细。
5. 页面自动显示供货单号、父订单 ID、目的地 supply ID、每托 cargo ID、平台状态和错误。API 完成不代表实物打包完成，计划仍沿用原库存与发货流程；后续平台状态由已有定时任务继续回读。

草稿有效期 30 分钟。无可用时段时可切换仓库重新查询；正式建单前可终止本次提交。终止提交不会自动取消已经确认的本地库存计划，库存释放仍使用计划原有的取消动作。

## 自动绑定、人工回填与计划状态

系统取得正式 `order_id` 后，通过完整供货明细校验自动绑定计划并回填 Ozon 供货单号。即使进程在记录提交的订单 ID 后中断，已有供货导入及每 15 分钟计划同步也会通过该 ID 恢复关联；已知 ID 按单回读，无需全账号搜索。

详情页保留送仓记录搜索选择和“人工回填供货单号”，支持平台单号或父订单 ID。尚未导入的单号先保存并排队回读，校验通过前保持原计划状态；关联时必须核对整单 SKU、数量、集群及每托唯一目的仓，不能重复绑定其他有效计划的供货单。人工点击绑定表示确认该平台供货；草稿校验通过后自动转为已确认并纳入现有库存占用口径。

已终止的申请可以人工绑定；失败或需复核的申请仅在已取得正式订单 ID 时开放人工关联，并且只能关联该订单。关联不清除货位写入失败或不确定的提交错误，也不把提交标为完成。没有订单 ID 的未知写入结果仍需先在平台复核。

| 平台证据 | 计划状态 |
| --- | --- |
| `DATA_FILLING` / `READY_TO_SUPPLY` 且整单匹配 | 草稿转已确认；保留人工打包中、已打包状态 |
| 父订单或任一目的地已进入收货、在途、验收阶段 | 已发出，记录发出时间 |
| 父订单及所有目的地均为 `COMPLETED` | 已完成，结束额外库存占用 |
| 已关联供货在发出前 `CANCELLED` | 已取消，释放计划占用 |
| 发出后取消、状态回退、拒收、逾期、目的仓变化或明细不符 | 保留原计划状态并显示复核错误 |

平台建单和货位写入成功不会自动推断实物“打包中／已打包”。两种关联方式均使用相同后台回读；页面每 30 秒读取本地状态并更新单号、计划状态及可用操作，提交执行期间每 3 秒读取。无状态变化时保留用户正在填写的表单，GET 与轮询不触发平台 API 或写库。

## 接口契约

平台凭证仅由后台从当前店铺关联的 `RawOzon::SellerAccount` 读取，不进入页面、提交快照或日志。

| 用途 | 接口和关键字段 |
| --- | --- |
| 搜索交货点 | `/v1/warehouse/fbo/list`，`filter_by_supply_type: [CREATE_TYPE_CROSSDOCK]`；搜索至少 4 字符 |
| 创建平台草稿 | `/v1/draft/direct/create`、`/v1/draft/crossdock/create`；`cluster_info: {macrolocal_cluster_id, items: [{sku, quantity}]}`、`deletion_sku_mode: FULL` |
| Cross-dock 交货点 | `delivery_info: {type: DROPOFF, drop_off_warehouse: {warehouse_id, warehouse_type}}`；仓库类型使用创建接口枚举，移除搜索结果的 `WAREHOUSE_TYPE_` 前缀 |
| 查询候选仓 | `/v2/draft/create/info`；仅接受匹配集群、供货方式且 `FULL_AVAILABLE` 的结果 |
| 核对完整商品组成 | `/v1/supply-order/bundle`；读取全部分页，按平台 SKU 精确比较数量，检查条码和量子 |
| 查询预约时段 | `/v2/draft/timeslot/info`；`draft_id`、`supply_type`、`selected_cluster_warehouses`、日期区间 |
| 创建正式供货单 | `/v2/draft/supply/create`；传同一仓库选择和平台原始时段 |
| 查询建单结果 | `/v2/draft/supply/create/status`；请求使用 `draft_id`，成功后取得 `order_id` |
| 回读正式供货 | 已有 `DailySync#sync_supply_orders(order_ids:)` 和 `OzonReconciler`；核对完整数量、集群及每托唯一目的地 |
| 写入箱/托货位 | `/v1/cargoes/create`；`delete_current_version: false`，`value.type` 为 `BOX` 或 `PALLET`，共用 `items: [{barcode, offer_id, quant, quantity}]` |
| 回读箱/托货位 | `/v2/cargoes/create/info`；用 `operation_id` 查询，按稳定的货运单元 key 精确匹配 cargo ID |
| 最终校验 | `/v1/cargoes/rules/get`；供货范围、货位存在、数量分配及所有适用必填规则必须通过 |

`quant` 来自 Ozon 返回的供货商品量子，不能使用本地外箱每箱件数代替。单托 SKU 数量必须是该量子的倍数；箱型货位每箱包含一个 SKU 的一个本地外箱，箱数与平台供货组成必须相符。普通货位最多 30 箱或 40 托，单箱货重最多 25kg；运输货位扩容暂不支持。平台减量、额外商品、拆分目的地、目的仓变化及必填信息缺失均会中止同步，保留已取得的外部 ID 和错误。当前不包含上门取货、多集群建单、保质期编辑和标签下载。

参考官方文档：[Seller API](https://docs.ozon.ru/api/seller/)、[FBO 创建流程](https://dev.ozon.ru/start/453-Protsess-sozdaniia-zaiavok-na-postavku-tovarov-FBO/)。`/v1/cargoes/create` 的 `ValueCargoType` schema 明确枚举为 `BOX`、`PALLET`，请求两者共用的货品结构；本地完整模拟覆盖箱型及托型链路。没有对真实 Ozon 执行写入，接口准入仍以平台实际响应及规则回读为准。旧 `platform_warehouse_allocation_stage2_api_research.md` 的 payload 是概念骨架，不能直接作为请求。

## 重复提交及异常恢复

计划详情页发起时锁定计划并读取数据库中的清单与托盘分配，校验表单版本，复用已有有效提交以防止重复创建；不接收前端提交的商品、数量、店铺或集群覆盖。计算器入口使用绑定用户、有效期两小时的签名快照；请求键和计划提交关联均有唯一索引。后台同一提交使用 PostgreSQL advisory lock 串行推进，不在外部写入期间持有数据库事务。写入前先持久化标记，防止进程中断后重新写入。

OzonClient 默认重试行为保留，新供货和货位写操作显式关闭重试。正式建单丢失响应后只查询原草稿的建单结果。草稿或货位写入结果不明时进入 `review_required`，不会自动重复创建或覆盖平台货位。平台明确失败或读取超时会展示错误；可恢复阶段提供重试入口，继续使用原 draft/order/operation ID。轮询每阶段最多 60 次，每次间隔 15 秒。每 15 分钟恢复扫描重新调度停滞的后台状态。

页面主 GET、工作台预览和状态轮询只读取本地数据。交货点搜索是明确的只读平台查询；所有外部写入都在后台任务中执行。提交记录保存实际发起人，正式写入前重新检查其管理权限及 SKU 可见范围；历史未记录发起人的提交沿用计划创建者。

## 验证

新增测试覆盖完整模拟链路、多托数量与 cargo ID、重复点击、签名失效、SKU 权限变化、库存不足、草稿过期、平台减量、条码/量子缺失、写入响应丢失、轮询上限、货位规则失败及目的仓变化。

状态查询性能测试比较 1 托和 10 托的未命中缓存 SQL 次数、最大 SQL 长度，并检查不实例化库存或订单记录；这是本地状态接口的合成数据检查，不代表整页或真实平台性能。

同步候选筛选另用 1 个及 10 个仅提交记录持有订单 ID 的合成计划验收：未命中缓存查询次数不随计划数增加，检查 SQL 长度及计划、店铺、提交记录的实例化数量，不加载原始供货记录。2026-10-20 本地开发库的只读筛选没有符合条件的待同步计划，因此该真实数据检查仅确认查询可执行，不作为批量性能结论；未运行平台 API 或对账写入。

计划详情发起申请的合成数据回归比较 1 托与 10 托，检查本地 POST 的未命中缓存 SQL 次数、最大 SQL 长度和库存记录实例化数量，确保逐托明细批量读取；后台平台 API 未包含在测量范围内。

相关 Rails 测试：

```sh
eval "$(/opt/homebrew/bin/rbenv init - zsh)"
SKIP_JS_BUILD=1 bin/rails test \
  test/controllers/reports/pallet_calculators_controller_test.rb \
  test/controllers/reports/pallet_workbenches_controller_test.rb \
  test/controllers/reports/pallet_plans_controller_test.rb \
  test/controllers/reports/ozon_supply_submissions_controller_test.rb \
  test/jobs/ec/pallet_plan_sync_job_test.rb \
  test/services/ec/pallet_plans/ \
  test/services/raw_ozon/supply_client_test.rb \
  test/services/raw_ozon/ozon_client_test.rb
node --check app/javascript/controllers/ozon_supply_controller.js
node --test test/javascript/ozon_supply_controller_test.mjs
```

当前依赖 `simple_apm` 会向可用语言追加 `zh-CN`，但全局菜单没有对应语言名称，直接运行上述页面测试会出现既有菜单翻译失败。验证项目配置的 `zh/en/ru` 时，可在测试进程初始化后显式限定语言，保持仓库配置不变：

```sh
SKIP_JS_BUILD=1 RAILS_ENV=test bin/rails runner \
  'I18n.available_locales = %i[zh en ru]; $LOAD_PATH.unshift(Rails.root.join("test").to_s); require "rails/test_unit/runner"; Rails::TestUnit::Runner.run(ARGV)' \
  test/controllers/reports/pallet_calculators_controller_test.rb \
  test/controllers/reports/pallet_workbenches_controller_test.rb \
  test/controllers/reports/pallet_plans_controller_test.rb \
  test/controllers/reports/ozon_supply_submissions_controller_test.rb \
  test/jobs/ec/pallet_plan_sync_job_test.rb \
  test/services/ec/pallet_plans/ \
  test/services/raw_ozon/supply_client_test.rb \
  test/services/raw_ozon/ozon_client_test.rb
```

本次不向真实店铺发单，平台结果通过注入客户端模拟验证。
