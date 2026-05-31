# 基础 ERP 系统设计规格

## 背景

当前项目已经具备 WB、Ozon 原始数据同步、SKU 主数据、SKU 成本、店铺、库存报表和周利润报表。后续 ERP 建设不应推倒重来，而应在现有 `Ec::*` 数据层上补齐采购、批次、费用分摊和运营任务。

本规格参考：

- `docs/电商沟通整理.md`
- `docs/现状-2026-05-29.md`

## 目标

第一版 ERP 建设目标是建立可持续扩展的经营数据底座：

- SKU 下面支持批次，成本先追踪到批次级。
- 国内采购、付款和费用分摊能进入系统台账。
- 批次成本可用于校验现有 SKU 成本，并为后续利润核算、补货测算和 Agent 建议提供依据。
- 运营任务可以从规则或人工录入中沉淀，支持补货、降价、清库、广告检查等动作记录。

## 非目标

第一版明确不做：

- 单件商品 ID、二维码和单件生命周期追踪。
- 完整多级审批流和权限系统。
- 国外公司回款、退税和当地财务报表核对。
- 多国家税务规则版本引擎。
- AI 自动写入采购、付款、成本等强财务数据。
- 新增 React/Vite 前端页面。

## 业务边界

基础 ERP 第一版覆盖 4 条主线：

1. **批次主线**：SKU → 批次 → 批次成本。
2. **采购主线**：供应商 → 采购单 → 采购明细 → 批次。
3. **费用主线**：费用记录 → 分摊到批次 → 单件批次成本。
4. **运营主线**：异常或人工判断 → 运营任务 → 执行状态。

报表、页面和服务都使用 Rails 原生 Controller + ERB + Turbo/Hotwire 风格，不新增 `frontend/` 下的 React/Vite 页面。

## 核心数据模型

### `Ec::SkuBatch`

SKU 批次。每个批次只属于一个 SKU。

建议字段：

- `sku_code`
- `batch_code`
- `status`
- `purchased_quantity`
- `received_quantity`
- `purchase_unit_price_cny`
- `expected_arrival_on`
- `received_on`
- `memo`

状态：

- `draft`
- `ordered`
- `in_transit`
- `received`
- `closed`

约束：

- `batch_code` 全局唯一。
- `sku_code` 必须关联已有 `Ec::Sku`。
- 数量不能为负。

### `Ec::Supplier`

供应商台账。

建议字段：

- `name`
- `contact_name`
- `phone`
- `wechat`
- `address`
- `is_active`
- `memo`

### `Ec::PurchaseOrder`

采购单主表。

建议字段：

- `order_no`
- `supplier_id`
- `ordered_on`
- `status`
- `currency`
- `memo`

状态：

- `draft`
- `ordered`
- `partially_received`
- `received`
- `cancelled`

### `Ec::PurchaseOrderItem`

采购单明细。每条明细关联一个 SKU 和一个批次。

建议字段：

- `purchase_order_id`
- `sku_code`
- `sku_batch_id`
- `quantity`
- `unit_price_cny`
- `memo`

约束：

- 同一采购单中，同一个批次只能出现一次。
- `quantity` 必须大于 0。

### `Ec::PaymentRequest`

付款申请和付款台账。

建议字段：

- `purchase_order_id`
- `payment_type`
- `amount_cny`
- `status`
- `requested_on`
- `approved_at`
- `paid_at`
- `memo`

付款类型：

- `deposit`
- `balance`
- `other`

状态：

- `pending`
- `approved`
- `paid`
- `cancelled`

第一版只记录状态，不做权限审批。`approved_at` 和 `paid_at` 为后续审批锁定预留。

### `Ec::CostAllocation`

费用分摊记录。

建议字段：

- `allocation_no`
- `cost_type`
- `allocation_method`
- `total_amount_cny`
- `allocated_on`
- `status`
- `memo`

费用类型：

- `international_freight`
- `customs`
- `certification`
- `warehouse`
- `misc`

分摊方式：

- `manual`
- `by_quantity`
- `by_purchase_amount`

状态：

- `draft`
- `locked`

### `Ec::CostAllocationItem`

费用分摊明细。

建议字段：

- `cost_allocation_id`
- `sku_batch_id`
- `amount_cny`
- `memo`

约束：

- `amount_cny` 不能为负。
- 当 `CostAllocation` 锁定时，明细金额合计必须等于主表 `total_amount_cny`。

### `Ec::OperationTask`

运营任务。

建议字段：

- `task_type`
- `status`
- `priority`
- `sku_code`
- `platform`
- `store_key`
- `title`
- `reason`
- `suggested_action`
- `owner_name`
- `due_on`
- `completed_at`

任务类型：

- `replenish`
- `reduce_price`
- `clearance`
- `increase_ad`
- `pause_ad`
- `check_loss`
- `check_order`

状态：

- `open`
- `in_progress`
- `done`
- `cancelled`

优先级：

- `low`
- `medium`
- `high`
- `urgent`

## 成本口径

第一版批次单件成本：

```text
批次单件成本 = 采购单价 + 批次已分摊费用合计 / 批次数量
```

说明：

- 批次数量优先使用 `received_quantity`，为空时使用 `purchased_quantity`。
- 批次数量为 0 时不计算单件成本。
- 批次成本只作为 ERP 经营台账和 SKU 成本校验依据。
- 周利润报表第一版仍沿用现有 `Ec::SkuCost` 和 `Ec::SkuPlatformCost`，不强行按批次拆销售。

## 页面规划

新增 ERP 页面命名空间：

- `/erp/sku_batches`：批次列表和详情。
- `/erp/suppliers`：供应商列表和详情。
- `/erp/purchase_orders`：采购单列表和详情。
- `/erp/cost_allocations`：费用分摊列表和详情。
- `/erp/operation_tasks`：运营任务列表和详情。

页面风格沿用现有 `app/views/layouts/application.html.erb`，保持密集、可扫描、偏运营后台。

第一版页面以只读和轻录入为主。写操作必须通过 Rails 表单提交，不在 GET 请求中写库。

## 服务规划

新增服务：

- `Ec::BatchCostSummary`：计算单个批次或一组批次的成本。
- `Ec::CostAllocationBuilder`：根据分摊方式生成分摊明细。
- `Ec::OperationTaskGenerator`：根据库存、利润等数据生成基础运营任务。

第一版生成任务只使用本地数据库数据，不调用平台 API。

## 测试策略

优先使用 Rails integration test 和 model test。

必测内容：

- 批次唯一性、状态、数量校验。
- 采购单与批次关联。
- 付款状态记录。
- 费用分摊金额合计校验。
- 批次单件成本计算。
- ERP 页面 HTML 渲染。
- 运营任务基础生成规则。

由于 `test/test_helper.rb` 中 `use_transactional_tests = false`，测试必须清理自己创建的数据，并使用唯一编号避免残留数据冲突。

## 上线顺序

1. 批次模型和批次页面。
2. 供应商、采购单、采购明细。
3. 付款申请。
4. 费用分摊和批次成本汇总。
5. 运营任务。
6. 站内通知和 Agent 只读上下文。

## 风险和约束

- 不要在第一版把 ERP 扩成完整财务系统。
- 成本锁定、审批和回款属于后续阶段。
- GET 页面必须保持只读。
- 平台原始数据和 ERP 台账要保持边界清晰，不要让同步服务直接修改 ERP 财务数据。
- AI 可以产生建议，但不能替代财务口径和审核。

