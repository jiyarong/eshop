# 发货单业务状态 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给 `ec_order_fulfillments` 新增与平台无关的 `business_status` 和 `return_business_status`，物理盘库的 FBS 板块改用"业务状态 × 退货业务状态"交叉表，格子可点开订单列表，且重构前后每个 SKU 的盘库数字只允许出现已评审的差异。

**Architecture:** 一个纯函数解析器 `Ec::FulfillmentBusinessStatus.resolve` 把平台源状态、WB 统计证据、关联退货映射成两个状态值；`Updater` 从数据库收集输入并写回发货单和订单汇总；三个入口（订单导入、退货同步、回填脚本）都调用 `Updater`。盘库查询用新字段的 group-by 代替现有 27 阶段的订单分布查询。

**Tech Stack:** Rails 8（Ruby 3.4.8）、PostgreSQL、Minitest、ERB + Turbo frame、Rails I18n（zh / en / ru）。

**Spec:** `docs/superpowers/specs/2026-10-13-fulfillment-business-status-design.md`（执行前通读，尤其第 4、5 节的映射表和交叉表）

## Global Constraints

- 字段名：`business_status`、`return_business_status`，同时加在 `ec_order_fulfillments`（权威）和 `ec_orders`（仅汇总展示）。
- 业务状态取值（6 个，字符串）：`awaiting_assembly`、`awaiting_dispatch`、`in_delivery`、`delivered`、`cancelled`、`needs_review`；默认 `needs_review`。
- 退货业务状态取值（6 个，字符串）：`none`、`expected`、`at_platform_side`、`returning_to_seller`、`received_by_seller`、`no_physical_return`；默认 `none`。
- 不修改 `ec_orders.order_status` 的取值和现有消费者（约 35 个文件在读它）。
- 订单商品到 SKU 的归属只走 `ec_sku_products` 硬关联（`SalesFunnelReports::SkuFunnelAnalysisQuery::ORDER_ITEM_JOIN`），不用 `ec_order_items.sku_code`。
- 页面 GET 请求保持只读：不触发重算、不调平台 API、不写库。
- 页面展示文案全部走 Rails I18n（`zh`、`en`、`ru`），不在 ERB、helper、controller 里写硬编码展示文案。
- 新 locale 键放进新文件 `config/locales/fulfillment_business_status.{zh,en,ru}.yml`，不要往已有的 `zh.yml`／`en.yml`／`ru.yml` 里塞（这三个文件有用户未提交的改动）。
- 迁移必须用 `bin/rails generate migration` 生成。
- 时间展示用 `display_time(...)`，表格用 `table_viewport`，弹窗沿用 `erp_modal` turbo frame，分页沿用 `reports/supply_orders/pagination`。
- 不启动 web server，不运行 `yarn build`／`vite build` 等前端构建；只运行相关的 Rails 测试文件，不跑全量测试（全量有约 140 个与本次无关的既有失败）。
- `test/test_helper.rb` 里 `use_transactional_tests = false`：测试必须用唯一 token 的数据并自行清理（复用 `test/support/book_ledger_fixtures.rb`）。
- 工作区有大量无关的未提交改动（`config/routes.rb`、`db/schema.rb`、`app/assets/stylesheets/application.css` 等）。只 `git add` 本任务相关路径；这几个共享文件用 `git add -p` 只暂存自己的 hunk。
- Ruby 环境：每个命令前先 `export PATH="$HOME/.rvm/rubies/ruby-3.4.8/bin:$PATH" GEM_HOME="$HOME/.rvm/gems/ruby-3.4.8" GEM_PATH="$HOME/.rvm/gems/ruby-3.4.8:$HOME/.rvm/gems/ruby-3.4.8@global"`（默认 shell 的 Ruby 3.0.0 跑不了 `bin/rails`）。
- 提交信息末尾加：`Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`。

## 基线与验收

重构前的物理盘库数字已记录：

- `docs/superpowers/baselines/2026-10-13-physical-stocktake-baseline.json`（236 个 SKU 的全部汇总指标和 FBS 订单行）
- `docs/superpowers/baselines/2026-10-13-physical-stocktake-baseline.md`（合计、记录范围、预期差异）
- `script/physical_stocktake_baseline.rb`（`capture` 与 `compare`，只读）

验收标准（Task 10）：对比脚本输出的有差异的 SKU 恰好是 20 个，合计 −48，且每个差异都能对应到基线文档里列出的三类原因；其余 216 个 SKU 的全部汇总指标逐项一致。

## File Structure

| 路径 | 动作 | 职责 |
|---|---|---|
| `app/services/ec/fulfillment_business_status.rb` | 创建 | 词表常量 + 纯函数 `resolve`，不读写数据库 |
| `app/services/ec/fulfillment_business_status/wb_stats_evidence.rb` | 创建 | 收集 WB 统计证据（`return` > `cancel` > `sale` > `order_only`） |
| `app/services/ec/fulfillment_business_status/updater.rb` | 创建 | 从数据库收集输入，调用 `resolve`，写发货单并汇总到订单 |
| `app/services/ec/fulfillment_business_status/backfill.rb` | 创建 | 批量重算，支持 `dry_run`，兼作一致性检查 |
| `script/backfill_fulfillment_business_status.rb` | 创建 | 回填脚本入口 |
| `db/migrate/<timestamp>_add_business_status_to_ec_fulfillments_and_orders.rb` | 生成 | 加列和索引 |
| `app/models/ec/order_fulfillment.rb`、`app/models/ec/order.rb` | 修改 | 词表校验 |
| `app/services/ec/order_import/ozon.rb`、`wb.rb` | 修改 | 导入时调用 `Updater` |
| `app/services/ec/returns/base_normalizer.rb` | 修改 | 退货保存后重算所属订单的发货单 |
| `app/services/ec/inventory_fbs_status_matrix_query.rb` | 创建 | 某 SKU 的 FBS 交叉表（格子、分类、汇总） |
| `app/services/ec/inventory_fbs_orders_query.rb` | 创建 | 某格子的订单明细（分页） |
| `app/services/ec/inventory_physical_reconciliation_query.rb` | 修改 | FBS 部分改读交叉表；去掉 `order_distribution:` 入参和 27 阶段、合成取消阶段逻辑 |
| `app/services/ec/inventory_page_row_query.rb`、`inventory_page_detail_query.rb` | 修改 | 去掉传给盘库查询的 `order_distribution` |
| `config/routes.rb`、`app/controllers/reports_controller.rb` | 修改 | 新增 `inventory_fbs_orders` 动作 |
| `app/views/reports/_inventory_physical_reconciliation.html.erb` | 修改 | FBS 板块换成交叉表 |
| `app/views/reports/inventory_fbs_orders.html.erb` | 创建 | 订单明细弹窗 |
| `app/assets/stylesheets/application.css` | 修改 | 交叉表格子的配色 |
| `config/locales/fulfillment_business_status.{zh,en,ru}.yml` | 创建 | 新增文案 |
| `test/services/ec/fulfillment_business_status_test.rb` 等 | 创建 | 各单元的测试 |

---

### Task 1: 提交基线记录

**Files:**
- Already created (untracked): `script/physical_stocktake_baseline.rb`、`docs/superpowers/baselines/2026-10-13-physical-stocktake-baseline.{json,md}`、`docs/superpowers/specs/2026-10-13-fulfillment-business-status-design.md`、本计划文件

**Interfaces:**
- Produces: 基线文件路径（Task 10 使用）

- [ ] **Step 1: 确认基线文件完整且可对比**

```bash
cd /Users/jiyarong/Developer/5/eshop
export PATH="$HOME/.rvm/rubies/ruby-3.4.8/bin:$PATH" GEM_HOME="$HOME/.rvm/gems/ruby-3.4.8" GEM_PATH="$HOME/.rvm/gems/ruby-3.4.8:$HOME/.rvm/gems/ruby-3.4.8@global"
ls -la docs/superpowers/baselines/
ruby -c script/physical_stocktake_baseline.rb
bin/rails runner script/physical_stocktake_baseline.rb compare \
  docs/superpowers/baselines/2026-10-13-physical-stocktake-baseline.json \
  docs/superpowers/baselines/2026-10-13-physical-stocktake-baseline.json 2>&1 | tail -1
```

Expected: `Syntax OK`，最后一行 `0 of 236 skus differ`。

- [ ] **Step 2: 提交**

```bash
git add script/physical_stocktake_baseline.rb \
  docs/superpowers/baselines/ \
  docs/superpowers/specs/2026-10-13-fulfillment-business-status-design.md \
  docs/superpowers/plans/2026-10-13-fulfillment-business-status.md
git commit -m "docs: record physical stocktake baseline and fulfillment business status design

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2: 解析器（纯函数）

**Files:**
- Create: `app/services/ec/fulfillment_business_status.rb`
- Test: `test/services/ec/fulfillment_business_status_test.rb`

**Interfaces:**
- Produces:
  - `Ec::FulfillmentBusinessStatus::BUSINESS_STATUSES` → `Array<String>`（6 个）
  - `Ec::FulfillmentBusinessStatus::RETURN_STATUSES` → `Array<String>`（6 个）
  - `Ec::FulfillmentBusinessStatus::Result` → `Data.define(:business_status, :return_business_status)`
  - `Ec::FulfillmentBusinessStatus.resolve(platform:, status:, source_status:, source_substatus:, stats_evidence: nil, returns: [], dispatched: false)` → `Result`
    - `platform`：`"wb"` 或 `"ozon"`；`status`：发货单归一化状态（`processing`／`shipped`／`delivered`／`cancelled`／`returned` 等）
    - `stats_evidence`：`nil`、`"return"`、`"cancel"`、`"sale"` 或 `"order_only"`（仅 WB）
    - `returns`：`Array<Hash>`，每个 `{ id:, at:, source_status:, process_status:, returned_to_seller: }`
    - `dispatched`：布尔值，或无参 callable（只在业务状态为 `cancelled` 且没有任何有效退货时才会被调用）

- [ ] **Step 1: 写失败的测试**

创建 `test/services/ec/fulfillment_business_status_test.rb`：

```ruby
require "test_helper"

class Ec::FulfillmentBusinessStatusTest < ActiveSupport::TestCase
  def resolve(**attributes)
    defaults = { platform: "wb", status: "processing", source_status: nil, source_substatus: nil }
    Ec::FulfillmentBusinessStatus.resolve(**defaults.merge(attributes))
  end

  def business(**attributes)
    resolve(**attributes).business_status
  end

  def return_status(**attributes)
    resolve(**attributes).return_business_status
  end

  def return_record(source_status: nil, process_status: "unknown", returned_to_seller: false, at: Time.zone.parse("2026-09-01 10:00"), id: 1)
    { id: id, at: at, source_status: source_status, process_status: process_status, returned_to_seller: returned_to_seller }
  end

  test "vocabulary matches the design" do
    assert_equal %w[awaiting_assembly awaiting_dispatch in_delivery delivered cancelled needs_review],
      Ec::FulfillmentBusinessStatus::BUSINESS_STATUSES
    assert_equal %w[none expected at_platform_side returning_to_seller received_by_seller no_physical_return],
      Ec::FulfillmentBusinessStatus::RETURN_STATUSES
  end

  test "maps WB marketplace statuses" do
    {
      [ "waiting", "new", "processing" ] => "awaiting_assembly",
      [ "waiting", "confirm", "processing" ] => "awaiting_dispatch",
      [ "waiting", "complete", "processing" ] => "in_delivery",
      [ "sorted", "complete", "shipped" ] => "in_delivery",
      [ "ready_for_pickup", "complete", "shipped" ] => "in_delivery",
      [ "postponed_delivery", "complete", "shipped" ] => "in_delivery",
      [ "accepted_by_carrier", "complete", "shipped" ] => "in_delivery",
      [ "sent_to_carrier", "complete", "shipped" ] => "in_delivery",
      [ "sold", "complete", "delivered" ] => "delivered",
      [ "canceled", "complete", "cancelled" ] => "cancelled",
      [ "canceled_by_client", "complete", "cancelled" ] => "cancelled",
      [ "declined_by_client", "new", "cancelled" ] => "cancelled",
      [ "defect", "complete", "cancelled" ] => "cancelled",
      [ "canceled_by_carrier", "complete", "cancelled" ] => "cancelled",
      [ "waiting", "cancel", "cancelled" ] => "cancelled",
      [ nil, nil, "processing" ] => "needs_review"
    }.each do |(source_status, source_substatus, status), expected|
      assert_equal expected, business(platform: "wb", status: status, source_status: source_status,
        source_substatus: source_substatus), [ source_status, source_substatus, status ].inspect
    end
  end

  test "WB statistics evidence outranks a stuck waiting status but not a cancel class status" do
    assert_equal "delivered",
      business(platform: "wb", source_status: "waiting", source_substatus: "new", stats_evidence: "sale")
    assert_equal "delivered",
      business(platform: "wb", source_status: "waiting", source_substatus: "new", stats_evidence: "return")
    assert_equal "cancelled",
      business(platform: "wb", source_status: "waiting", source_substatus: "new", stats_evidence: "cancel")
    assert_equal "cancelled",
      business(platform: "wb", source_status: "canceled_by_client", source_substatus: "complete",
        status: "returned", stats_evidence: "return")
    assert_equal "awaiting_assembly",
      business(platform: "wb", source_status: "waiting", source_substatus: "new", stats_evidence: "order_only")
  end

  test "WB sold and returned orders without a platform status are delivered" do
    assert_equal "delivered", business(platform: "wb", status: "delivered")
    assert_equal "delivered", business(platform: "wb", status: "returned", source_status: "sold", source_substatus: "complete")
  end

  test "maps Ozon posting statuses" do
    {
      [ "awaiting_packaging", "posting_created" ] => "awaiting_assembly",
      [ "awaiting_deliver", "posting_transferring_to_delivery" ] => "awaiting_dispatch",
      [ "awaiting_delivery", nil ] => "awaiting_dispatch",
      [ "delivering", "posting_in_pickup_point" ] => "in_delivery",
      [ "delivering", "posting_on_way_to_city" ] => "in_delivery",
      [ "delivering", "posting_in_carriage" ] => "in_delivery",
      [ "delivering", "posting_transferred_to_courier_service" ] => "in_delivery",
      [ "driver_pickup", nil ] => "in_delivery",
      [ "sent_by_seller", nil ] => "in_delivery",
      [ "delivered", "posting_received" ] => "delivered",
      [ "delivered", "posting_delivered" ] => "delivered",
      [ "cancelled", "posting_canceled" ] => "cancelled",
      [ "not_accepted", nil ] => "cancelled",
      [ "delivering", "posting_returned_to_warehouse" ] => "cancelled",
      [ "awaiting_approve", nil ] => "needs_review",
      [ "arbitration", nil ] => "needs_review"
    }.each do |(source_status, source_substatus), expected|
      assert_equal expected, business(platform: "ozon", source_status: source_status,
        source_substatus: source_substatus), [ source_status, source_substatus ].inspect
    end
  end

  test "maps Ozon return statuses" do
    {
      "ReceivedBySeller" => "received_by_seller",
      "MovingToSeller" => "returning_to_seller",
      "ReadyForSeller" => "returning_to_seller",
      "ArrivedAtReturnPlace" => "returning_to_seller",
      "OnSellerApproval" => "at_platform_side",
      "WaitingShipment" => "at_platform_side",
      "Approved" => "at_platform_side",
      "MovingToOzon" => "at_platform_side",
      "ReturnedToOzon" => "at_platform_side",
      "MoneyReturned" => "no_physical_return",
      "PartialCompensationReturned" => "no_physical_return",
      "Cancelled" => "no_physical_return",
      "CancelledDisputeNotOpen" => "no_physical_return",
      "Rejected" => "no_physical_return",
      "WriteOff" => "no_physical_return",
      "Utilized" => "no_physical_return",
      "PotentiallyLost" => "no_physical_return",
      "SomethingNew" => "at_platform_side"
    }.each do |source_status, expected|
      assert_equal expected,
        return_status(platform: "ozon", source_status: "delivered", source_substatus: "posting_received",
          status: "delivered", returns: [ return_record(source_status: source_status) ]), source_status
    end
  end

  test "maps WB goods return records" do
    base = { platform: "wb", source_status: "sold", source_substatus: "complete", status: "delivered" }
    assert_equal "received_by_seller",
      return_status(**base, returns: [ return_record(source_status: "Выдано", process_status: "completed") ])
    assert_equal "received_by_seller",
      return_status(**base, returns: [ return_record(returned_to_seller: true) ])
    assert_equal "returning_to_seller",
      return_status(**base, returns: [ return_record(source_status: "Готов к выдаче", process_status: "ready_for_seller_pickup") ])
    assert_equal "at_platform_side",
      return_status(**base, returns: [ return_record(source_status: "В пути в пвз", process_status: "unknown") ])
  end

  test "uses the latest valid return and falls back to no physical return" do
    base = { platform: "ozon", source_status: "delivered", source_substatus: "posting_received", status: "delivered" }
    older = return_record(source_status: "ReceivedBySeller", id: 1, at: Time.zone.parse("2026-09-01"))
    newer_cancelled = return_record(source_status: "Cancelled", id: 2, at: Time.zone.parse("2026-09-05"))
    newest_active = return_record(source_status: "MovingToOzon", id: 3, at: Time.zone.parse("2026-09-09"))

    assert_equal "received_by_seller", return_status(**base, returns: [ older, newer_cancelled ])
    assert_equal "at_platform_side", return_status(**base, returns: [ older, newer_cancelled, newest_active ])
    assert_equal "no_physical_return", return_status(**base, returns: [ newer_cancelled ])
  end

  test "marks cancelled fulfillments that left the warehouse as expected" do
    base = { platform: "wb", source_status: "canceled_by_client", source_substatus: "complete", status: "cancelled" }
    assert_equal "expected", return_status(**base, dispatched: true)
    assert_equal "none", return_status(**base, dispatched: false)
    assert_equal "none",
      return_status(platform: "wb", source_status: "sold", source_substatus: "complete", status: "delivered", dispatched: true)
  end

  test "WB return evidence without a return record means the goods are on the platform side" do
    base = { platform: "wb", source_status: "canceled_by_client", source_substatus: "complete", status: "returned",
             stats_evidence: "return", dispatched: true }
    assert_equal "at_platform_side", return_status(**base)
    assert_equal "at_platform_side",
      return_status(platform: "wb", source_status: "sold", source_substatus: "complete", status: "returned")
  end

  test "dispatch evidence is only evaluated for cancelled fulfillments without a return" do
    calls = 0
    probe = -> { calls += 1; true }

    return_status(platform: "wb", source_status: "sold", source_substatus: "complete", status: "delivered", dispatched: probe)
    assert_equal 0, calls

    return_status(platform: "wb", source_status: "canceled_by_client", source_substatus: "complete",
      status: "cancelled", dispatched: probe)
    assert_equal 1, calls
  end

  test "resolve returns both axes together" do
    result = resolve(platform: "ozon", source_status: "delivered", source_substatus: "posting_received",
      status: "delivered", returns: [ return_record(source_status: "ReceivedBySeller") ])

    assert_equal "delivered", result.business_status
    assert_equal "received_by_seller", result.return_business_status
  end
end
```

- [ ] **Step 2: 运行测试确认失败**

```bash
export PATH="$HOME/.rvm/rubies/ruby-3.4.8/bin:$PATH" GEM_HOME="$HOME/.rvm/gems/ruby-3.4.8" GEM_PATH="$HOME/.rvm/gems/ruby-3.4.8:$HOME/.rvm/gems/ruby-3.4.8@global"
bin/rails test test/services/ec/fulfillment_business_status_test.rb
```

Expected: 全部 ERROR，`uninitialized constant Ec::FulfillmentBusinessStatus`。

- [ ] **Step 3: 实现解析器**

创建 `app/services/ec/fulfillment_business_status.rb`：

```ruby
module Ec
  # Flattens the platform specific order and return statuses of one fulfillment (posting) into two platform
  # neutral values: where the goods are in the delivery chain (business status) and where the returning goods
  # are (return business status). Pure functions: the caller (Updater) gathers the inputs.
  module FulfillmentBusinessStatus
    BUSINESS_STATUSES = %w[
      awaiting_assembly awaiting_dispatch in_delivery delivered cancelled needs_review
    ].freeze
    RETURN_STATUSES = %w[
      none expected at_platform_side returning_to_seller received_by_seller no_physical_return
    ].freeze

    Result = Data.define(:business_status, :return_business_status)

    WB_CANCEL_STATUSES = %w[canceled cancelled canceled_by_client declined_by_client defect canceled_by_carrier].freeze
    WB_CANCEL_SUBSTATUSES = %w[cancel cancelled cancel_carrier].freeze
    WB_DELIVERED_STATUSES = %w[sold returned].freeze
    WB_IN_DELIVERY_STATUSES = %w[sorted ready_for_pickup postponed_delivery accepted_by_carrier sent_to_carrier].freeze
    WB_WAITING_SUBSTATUSES = {
      "new" => "awaiting_assembly", "confirm" => "awaiting_dispatch", "complete" => "in_delivery"
    }.freeze

    OZON_CANCEL_STATUSES = %w[cancelled not_accepted].freeze
    # A posting handed to delivery and then returned to the Ozon warehouse is treated as cancelled; the dispatch
    # evidence then marks it as expected back.
    OZON_CANCEL_SUBSTATUSES = %w[posting_canceled posting_returned_to_warehouse].freeze
    OZON_DELIVERED_STATUSES = %w[delivered].freeze
    OZON_DELIVERED_SUBSTATUSES = %w[posting_received posting_delivered].freeze
    OZON_ASSEMBLY_STATUSES = %w[awaiting_packaging].freeze
    OZON_DISPATCH_STATUSES = %w[awaiting_deliver awaiting_delivery].freeze
    OZON_IN_DELIVERY_STATUSES = %w[delivering driver_pickup sent_by_seller].freeze
    OZON_IN_DELIVERY_SUBSTATUSES = %w[
      posting_transferred_to_courier_service posting_in_carriage posting_on_way_to_city posting_in_pickup_point
    ].freeze

    OZON_RETURN_STATES = {
      "ReceivedBySeller" => "received_by_seller",
      "MovingToSeller" => "returning_to_seller",
      "ReadyForSeller" => "returning_to_seller",
      "ArrivedAtReturnPlace" => "returning_to_seller",
      "OnSellerApproval" => "at_platform_side",
      "WaitingShipment" => "at_platform_side",
      "Approved" => "at_platform_side",
      "MovingToOzon" => "at_platform_side",
      "ReturnedToOzon" => "at_platform_side",
      "MoneyReturned" => "no_physical_return",
      "PartialCompensationReturned" => "no_physical_return",
      "Cancelled" => "no_physical_return",
      "CancelledDisputeNotOpen" => "no_physical_return",
      "Rejected" => "no_physical_return",
      "WriteOff" => "no_physical_return",
      "Utilized" => "no_physical_return",
      "PotentiallyLost" => "no_physical_return"
    }.freeze

    module_function

    def resolve(platform:, status:, source_status:, source_substatus:, stats_evidence: nil, returns: [], dispatched: false)
      business = business_status(
        platform: platform, status: status, source_status: source_status,
        source_substatus: source_substatus, stats_evidence: stats_evidence
      )
      Result.new(
        business_status: business,
        return_business_status: return_business_status(
          platform: platform, business_status: business, status: status, returns: returns,
          dispatched: dispatched, stats_evidence: stats_evidence
        )
      )
    end

    def business_status(platform:, status:, source_status:, source_substatus:, stats_evidence: nil)
      source_status = source_status.to_s
      source_substatus = source_substatus.to_s
      if platform.to_s == "wb"
        wb_business_status(status.to_s, source_status, source_substatus, stats_evidence.to_s)
      else
        ozon_business_status(source_status, source_substatus)
      end
    end

    def wb_business_status(status, source_status, source_substatus, stats_evidence)
      if status == "cancelled" || stats_evidence == "cancel" ||
          source_status.in?(WB_CANCEL_STATUSES) || source_substatus.in?(WB_CANCEL_SUBSTATUSES)
        return "cancelled"
      end
      if stats_evidence.in?(%w[return sale]) || status.in?(%w[delivered returned]) ||
          source_status.in?(WB_DELIVERED_STATUSES)
        return "delivered"
      end
      return WB_WAITING_SUBSTATUSES.fetch(source_substatus, "needs_review") if source_status == "waiting"
      return "in_delivery" if source_status.in?(WB_IN_DELIVERY_STATUSES)

      "needs_review"
    end

    def ozon_business_status(source_status, source_substatus)
      return "cancelled" if source_status.in?(OZON_CANCEL_STATUSES) || source_substatus.in?(OZON_CANCEL_SUBSTATUSES)
      if source_status.in?(OZON_DELIVERED_STATUSES) || source_substatus.in?(OZON_DELIVERED_SUBSTATUSES)
        return "delivered"
      end
      return "awaiting_assembly" if source_status.in?(OZON_ASSEMBLY_STATUSES)
      return "awaiting_dispatch" if source_status.in?(OZON_DISPATCH_STATUSES)
      if source_status.in?(OZON_IN_DELIVERY_STATUSES) || source_substatus.in?(OZON_IN_DELIVERY_SUBSTATUSES)
        return "in_delivery"
      end

      "needs_review"
    end

    # State of one return record. Unknown Ozon statuses count as still in progress on the platform side.
    def return_state(platform:, source_status:, process_status:, returned_to_seller:)
      return OZON_RETURN_STATES.fetch(source_status.to_s, "at_platform_side") if platform.to_s == "ozon"

      if returned_to_seller || source_status.to_s == "Выдано" || process_status.to_s == "completed"
        return "received_by_seller"
      end
      return "returning_to_seller" if process_status.to_s == "ready_for_seller_pickup"

      "at_platform_side"
    end

    def return_business_status(platform:, business_status:, status:, returns:, dispatched:, stats_evidence: nil)
      states = Array(returns).sort_by { |item| [ item[:at].to_f, item[:id].to_i ] }.map do |item|
        return_state(
          platform: platform, source_status: item[:source_status], process_status: item[:process_status],
          returned_to_seller: item[:returned_to_seller]
        )
      end
      chosen = states.reject { |state| state == "no_physical_return" }.last || states.last
      return chosen if chosen

      return "at_platform_side" if platform.to_s == "wb" && (status.to_s == "returned" || stats_evidence.to_s == "return")
      return "none" unless business_status == "cancelled"

      # Only a cancelled fulfillment without a return needs to know whether it left the warehouse.
      dispatched = dispatched.call if dispatched.respond_to?(:call)
      dispatched ? "expected" : "none"
    end
  end
end
```

- [ ] **Step 4: 运行测试确认通过**

```bash
bin/rails test test/services/ec/fulfillment_business_status_test.rb
```

Expected: 12 runs, 0 failures, 0 errors。

- [ ] **Step 5: 提交**

```bash
git add app/services/ec/fulfillment_business_status.rb test/services/ec/fulfillment_business_status_test.rb
git commit -m "feat: add platform neutral fulfillment business status resolver

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3: 迁移与模型校验

**Files:**
- Generate: `db/migrate/<timestamp>_add_business_status_to_ec_fulfillments_and_orders.rb`
- Modify: `app/models/ec/order_fulfillment.rb`、`app/models/ec/order.rb`
- Modify (by migration): `db/schema.rb`
- Test: `test/models/ec/business_status_validation_test.rb`

**Interfaces:**
- Consumes: `Ec::FulfillmentBusinessStatus::BUSINESS_STATUSES`、`RETURN_STATUSES`（Task 2）
- Produces: `ec_order_fulfillments.business_status`、`ec_order_fulfillments.return_business_status`、`ec_orders.business_status`、`ec_orders.return_business_status`（均 `string null: false`）

- [ ] **Step 1: 写失败的测试**

创建 `test/models/ec/business_status_validation_test.rb`：

```ruby
require "test_helper"

class Ec::BusinessStatusValidationTest < ActiveSupport::TestCase
  test "fulfillment rejects values outside the vocabulary" do
    fulfillment = Ec::OrderFulfillment.new(business_status: "bogus", return_business_status: "bogus")
    fulfillment.valid?

    assert_includes fulfillment.errors.attribute_names, :business_status
    assert_includes fulfillment.errors.attribute_names, :return_business_status
  end

  test "order rejects values outside the vocabulary" do
    order = Ec::Order.new(business_status: "bogus", return_business_status: "bogus")
    order.valid?

    assert_includes order.errors.attribute_names, :business_status
    assert_includes order.errors.attribute_names, :return_business_status
  end

  test "new records default to needs_review and none" do
    assert_equal "needs_review", Ec::OrderFulfillment.new.business_status
    assert_equal "none", Ec::OrderFulfillment.new.return_business_status
    assert_equal "needs_review", Ec::Order.new.business_status
    assert_equal "none", Ec::Order.new.return_business_status
  end
end
```

- [ ] **Step 2: 运行测试确认失败**

```bash
bin/rails test test/models/ec/business_status_validation_test.rb
```

Expected: ERROR（`unknown attribute 'business_status'`）。

- [ ] **Step 3: 生成并填写迁移**

```bash
bin/rails generate migration AddBusinessStatusToEcFulfillmentsAndOrders
```

打开生成的文件，保留生成的类名和 `ActiveRecord::Migration[...]` 版本，方法体改为：

```ruby
  def change
    add_column :ec_order_fulfillments, :business_status, :string, null: false, default: "needs_review"
    add_column :ec_order_fulfillments, :return_business_status, :string, null: false, default: "none"
    add_column :ec_orders, :business_status, :string, null: false, default: "needs_review"
    add_column :ec_orders, :return_business_status, :string, null: false, default: "none"

    add_index :ec_order_fulfillments, %i[business_status return_business_status],
      name: "idx_ec_order_fulfillments_business_statuses"
    add_index :ec_orders, %i[business_status return_business_status],
      name: "idx_ec_orders_business_statuses"
  end
```

- [ ] **Step 4: 加模型校验**

在 `app/models/ec/order_fulfillment.rb` 的 `validates :fulfillment_key, uniqueness: ...` 之后加：

```ruby
    validates :business_status, inclusion: { in: Ec::FulfillmentBusinessStatus::BUSINESS_STATUSES }
    validates :return_business_status, inclusion: { in: Ec::FulfillmentBusinessStatus::RETURN_STATUSES }
```

在 `app/models/ec/order.rb` 的 `validates :order_key, uniqueness: ...` 之后加同样两行。

- [ ] **Step 5: 迁移并运行测试**

```bash
bin/rails db:migrate
git diff --stat db/schema.rb
bin/rails test test/models/ec/business_status_validation_test.rb
```

Expected: `db/schema.rb` 里新增 4 列和 2 个索引（该文件原本就有用户的未提交改动，只会多出这些 hunk）；测试 3 runs, 0 failures。

- [ ] **Step 6: 提交**

```bash
git add db/migrate/*_add_business_status_to_ec_fulfillments_and_orders.rb \
  app/models/ec/order_fulfillment.rb app/models/ec/order.rb \
  test/models/ec/business_status_validation_test.rb
git add -p db/schema.rb   # 只暂存 ec_order_fulfillments / ec_orders 新增列、索引和 schema version 的 hunk
git commit -m "feat: add business status columns to ec fulfillments and orders

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 4: WB 统计证据与 Updater

**Files:**
- Create: `app/services/ec/fulfillment_business_status/wb_stats_evidence.rb`
- Create: `app/services/ec/fulfillment_business_status/updater.rb`
- Test: `test/services/ec/fulfillment_business_status/updater_test.rb`

**Interfaces:**
- Consumes: `Ec::FulfillmentBusinessStatus.resolve`、`Result`（Task 2），新列（Task 3）
- Produces:
  - `Ec::FulfillmentBusinessStatus::WbStatsEvidence.for_orders(order_ids)` → `Hash{Integer => String}`，`order_id => "return"|"cancel"|"sale"|"order_only"`（没有统计订单的订单不在 hash 里）
  - `Ec::FulfillmentBusinessStatus::Updater.call(fulfillment, stats_evidence: :load, write: true)` → `Result`
    - `stats_evidence`：`:load`（默认，单个订单现查）、`nil`、或字符串（批量调用时由调用方预先算好传入）
    - `write: false` 时不写库（回填的 dry run 用）
  - `Ec::FulfillmentBusinessStatus::Updater.for_order(order)` → 重算该订单的全部发货单
  - `Ec::FulfillmentBusinessStatus::Updater.rollup_order(order)` → 把发货单状态汇总写回订单

- [ ] **Step 1: 写失败的测试**

创建 `test/services/ec/fulfillment_business_status/updater_test.rb`：

```ruby
require "test_helper"
require_relative "../../../support/book_ledger_fixtures"

class Ec::FulfillmentBusinessStatus::UpdaterTest < ActiveSupport::TestCase
  include BookLedgerFixtures

  setup { setup_ledger_world }
  teardown do
    RawWb::StatsSale.where(account_id: @wb_account&.id).delete_all
    RawWb::StatsOrder.where(account_id: @wb_account&.id).delete_all
    teardown_ledger_world
  end

  def statuses(fulfillment)
    fulfillment.reload.attributes.values_at("business_status", "return_business_status")
  end

  test "Ozon delivered posting with a seller received return" do
    order = ledger_order(platform: "ozon", status: "delivered", source_status: "delivered",
      source_substatus: "posting_received")
    ledger_return(order, source_status: "ReceivedBySeller")
    fulfillment = order.fulfillments.first

    result = Ec::FulfillmentBusinessStatus::Updater.call(fulfillment)

    assert_equal %w[delivered received_by_seller], [ result.business_status, result.return_business_status ]
    assert_equal %w[delivered received_by_seller], statuses(fulfillment)
    assert_equal %w[delivered received_by_seller], order.reload.attributes.values_at("business_status", "return_business_status")
  end

  test "Ozon cancelled posting handed to delivery without a return is expected back" do
    order = ledger_order(platform: "ozon", status: "cancelled", source_status: "cancelled",
      source_substatus: "posting_canceled")
    fulfillment = order.fulfillments.first
    RawOzon::PostingFbs.create!(
      account: @ozon_account, posting_number: fulfillment.external_fulfillment_id, status: "cancelled",
      substatus: "posting_canceled", delivering_date: 2.days.ago, raw_json: {}, created_at: Time.current
    )

    Ec::FulfillmentBusinessStatus::Updater.call(fulfillment)

    assert_equal %w[cancelled expected], statuses(fulfillment)
  end

  test "Ozon cancelled posting that never left stays without a return" do
    order = ledger_order(platform: "ozon", status: "cancelled", source_status: "cancelled",
      source_substatus: "posting_canceled")
    fulfillment = order.fulfillments.first
    RawOzon::PostingFbs.create!(
      account: @ozon_account, posting_number: fulfillment.external_fulfillment_id, status: "cancelled",
      substatus: "posting_canceled", delivering_date: nil, raw_json: {}, created_at: Time.current
    )

    Ec::FulfillmentBusinessStatus::Updater.call(fulfillment)

    assert_equal %w[cancelled none], statuses(fulfillment)
  end

  test "WB cancelled order is expected back when the raw order supplier status is complete" do
    order = ledger_order(platform: "wb", status: "cancelled", source_status: "canceled_by_client",
      source_substatus: "cancelled")
    raw_order = RawWb::Order.create!(
      account: @wb_account, wb_order_id: 70_000_000_000 + @token.to_i(16), nm_id: @wb_product.product_id.to_i,
      delivery_type: "fbs", wb_status: "canceled_by_client", supplier_status: "complete"
    )
    Ec::OrderSourceLink.create!(
      order: order, platform: "wb", source_type: "RawWb::Order", source_id: raw_order.id,
      source_role: "primary", source_key: raw_order.wb_order_id.to_s
    )

    Ec::FulfillmentBusinessStatus::Updater.call(order.fulfillments.first)

    assert_equal %w[cancelled expected], statuses(order.fulfillments.first)
  end

  test "WB order stuck in waiting new with a statistics sale is delivered" do
    order = ledger_order(platform: "wb", status: "processing", source_status: "waiting", source_substatus: "new")
    stats_order = RawWb::StatsOrder.create!(
      account: @wb_account, srid: "SRID-#{@token}", g_number: "G-#{@token}", nm_id: @wb_product.product_id.to_i,
      order_date: 3.days.ago, last_change_date: 1.day.ago, is_cancel: false, synced_at: Time.current
    )
    Ec::OrderSourceLink.create!(
      order: order, platform: "wb", source_type: "RawWb::StatsOrder", source_id: stats_order.id,
      source_role: "primary", source_key: stats_order.srid
    )
    RawWb::StatsSale.create!(
      account: @wb_account, sale_id: "S#{@token}", srid: stats_order.srid, g_number: stats_order.g_number,
      sale_date: 1.day.ago, is_storno: false, synced_at: Time.current
    )

    assert_equal({ order.id => "sale" }, Ec::FulfillmentBusinessStatus::WbStatsEvidence.for_orders([ order.id ]))
    Ec::FulfillmentBusinessStatus::Updater.call(order.fulfillments.first)

    assert_equal %w[delivered none], statuses(order.fulfillments.first)
  end

  test "statistics evidence prefers return over cancel over sale" do
    order = ledger_order(platform: "wb", status: "processing", source_status: "waiting", source_substatus: "new")
    stats_order = RawWb::StatsOrder.create!(
      account: @wb_account, srid: "SRID-#{@token}", g_number: "G-#{@token}", nm_id: @wb_product.product_id.to_i,
      order_date: 3.days.ago, last_change_date: 1.day.ago, is_cancel: true, synced_at: Time.current
    )
    Ec::OrderSourceLink.create!(
      order: order, platform: "wb", source_type: "RawWb::StatsOrder", source_id: stats_order.id,
      source_role: "primary", source_key: stats_order.srid
    )
    assert_equal "cancel", Ec::FulfillmentBusinessStatus::WbStatsEvidence.for_orders([ order.id ])[order.id]

    RawWb::StatsSale.create!(
      account: @wb_account, sale_id: "R#{@token}", srid: stats_order.srid, g_number: stats_order.g_number,
      sale_date: 1.day.ago, is_storno: false, synced_at: Time.current
    )
    assert_equal "return", Ec::FulfillmentBusinessStatus::WbStatsEvidence.for_orders([ order.id ])[order.id]
  end

  test "return attaches through the order item first, then the posting number, then a sole fulfillment" do
    order = ledger_order(platform: "ozon", status: "delivered", source_status: "delivered",
      source_substatus: "posting_received")
    second = order.fulfillments.create!(
      platform: "ozon", store: @ozon_store, external_fulfillment_id: "POSTING-2-#{@token}",
      fulfillment_key: "ozon:#{@ozon_store.id}:POSTING-2-#{@token}", fulfillment_type: "fbo", status: "delivered",
      source_status: "delivered", source_substatus: "posting_received"
    )
    second_item = order.items.create!(
      fulfillment: second, platform: "ozon", store: @ozon_store, external_item_id: "ITEM-2-#{@token}",
      platform_sku_id: @ozon_product.platform_sku_id, quantity: 1
    )
    record = ledger_return(order, source_status: "ReceivedBySeller")
    record.items.first.update!(order_item: second_item)

    Ec::FulfillmentBusinessStatus::Updater.for_order(order)

    assert_equal %w[delivered none], statuses(order.fulfillments.find_by!(fulfillment_type: "fbs"))
    assert_equal %w[delivered received_by_seller], statuses(second)
  end

  test "order summary shows the least finished fulfillment and the most unresolved return" do
    order = ledger_order(platform: "ozon", status: "delivered", source_status: "delivered",
      source_substatus: "posting_received")
    order.fulfillments.create!(
      platform: "ozon", store: @ozon_store, external_fulfillment_id: "POSTING-3-#{@token}",
      fulfillment_key: "ozon:#{@ozon_store.id}:POSTING-3-#{@token}", fulfillment_type: "fbs", status: "processing",
      source_status: "awaiting_packaging", source_substatus: "posting_created"
    )

    Ec::FulfillmentBusinessStatus::Updater.for_order(order)

    assert_equal %w[awaiting_assembly none], order.reload.attributes.values_at("business_status", "return_business_status")
  end

  test "write false computes without touching the database" do
    order = ledger_order(platform: "ozon", status: "delivered", source_status: "delivered",
      source_substatus: "posting_received")
    fulfillment = order.fulfillments.first

    result = Ec::FulfillmentBusinessStatus::Updater.call(fulfillment, write: false)

    assert_equal "delivered", result.business_status
    assert_equal %w[needs_review none], statuses(fulfillment)
  end
end
```

注意：`RawWb::StatsOrder`、`RawWb::StatsSale` 的必填字段以 `db/schema.rb` 为准。如果上面的 `create!` 因为缺少非空列失败，补齐对应列即可，不要改断言。

- [ ] **Step 2: 运行测试确认失败**

```bash
bin/rails test test/services/ec/fulfillment_business_status/updater_test.rb
```

Expected: ERROR，`uninitialized constant Ec::FulfillmentBusinessStatus::Updater`。

- [ ] **Step 3: 实现 WB 统计证据**

创建 `app/services/ec/fulfillment_business_status/wb_stats_evidence.rb`：

```ruby
module Ec
  module FulfillmentBusinessStatus
    # Evidence of what happened to a WB order according to the Statistics API. It is the same evidence the order
    # sales distribution uses, because the marketplace status of an order can stay stuck on `waiting`.
    # Per order the strongest evidence wins: return > cancel > sale > order_only.
    class WbStatsEvidence
      PRECEDENCE = %w[return cancel sale order_only].freeze

      def self.for_orders(order_ids)
        order_ids = Array(order_ids).compact.uniq
        return {} if order_ids.empty?

        links = Ec::OrderSourceLink
          .where(order_id: order_ids, source_type: "RawWb::StatsOrder", source_role: "primary")
          .pluck(:order_id, :source_id)
        return {} if links.empty?

        stats_orders = RawWb::StatsOrder.where(id: links.map(&:last)).index_by(&:id)
        srids = stats_orders.values.map(&:srid).compact_blank.uniq
        g_numbers = stats_orders.values.map(&:g_number).compact_blank.uniq
        sales = RawWb::StatsSale.where(is_storno: [ false, nil ])
          .where("srid IN (:srids) OR g_number IN (:g_numbers)", srids: srids, g_numbers: g_numbers).to_a
        sales_by_srid = sales.group_by { |sale| [ sale.account_id, sale.srid ] }
        sales_by_g_number = sales.group_by { |sale| [ sale.account_id, sale.g_number ] }

        links.group_by(&:first).to_h do |order_id, order_links|
          keys = order_links.filter_map do |_order_id, source_id|
            stats_order = stats_orders[source_id]
            next unless stats_order

            matching = sales_by_srid[[ stats_order.account_id, stats_order.srid ]].to_a
            matching = sales_by_g_number[[ stats_order.account_id, stats_order.g_number ]].to_a if matching.empty?
            evidence_key(stats_order, matching)
          end
          [ order_id, PRECEDENCE.find { |key| keys.include?(key) } ]
        end.compact_blank
      end

      def self.evidence_key(stats_order, sales)
        return "return" if sales.any? { |sale| sale.sale_id.to_s.start_with?("R") }
        return "cancel" if stats_order.is_cancel?
        return "sale" if sales.any? { |sale| !sale.sale_id.to_s.start_with?("R") }

        "order_only"
      end
      private_class_method :evidence_key
    end
  end
end
```

- [ ] **Step 4: 实现 Updater**

创建 `app/services/ec/fulfillment_business_status/updater.rb`：

```ruby
module Ec
  module FulfillmentBusinessStatus
    # Gathers the inputs of one fulfillment from the database, resolves its two business statuses and writes them
    # (plus the order summary). The only place that touches the database for this feature.
    class Updater
      BUSINESS_ROLLUP = %w[needs_review awaiting_assembly awaiting_dispatch in_delivery delivered cancelled].freeze
      RETURN_ROLLUP = %w[expected at_platform_side returning_to_seller received_by_seller no_physical_return none].freeze
      WB_DISPATCHED_SUPPLIER_STATUS = "complete".freeze

      def self.call(fulfillment, stats_evidence: :load, write: true)
        new(fulfillment, stats_evidence: stats_evidence).call(write: write)
      end

      def self.for_order(order)
        order.fulfillments.reload.each { |fulfillment| call(fulfillment) }
        rollup_order(order)
      end

      def self.rollup_order(order)
        pairs = Ec::OrderFulfillment.where(order_id: order.id).pluck(:business_status, :return_business_status)
        return if pairs.empty?

        business = BUSINESS_ROLLUP.find { |value| pairs.any? { |pair| pair.first == value } } || "needs_review"
        returns = RETURN_ROLLUP.find { |value| pairs.any? { |pair| pair.last == value } } || "none"
        return if order.business_status == business && order.return_business_status == returns

        order.update_columns(business_status: business, return_business_status: returns)
      end

      def initialize(fulfillment, stats_evidence: :load)
        @fulfillment = fulfillment
        @stats_evidence = stats_evidence
      end

      def call(write: true)
        result = resolve
        persist(result) if write
        result
      end

      private

      attr_reader :fulfillment

      def resolve
        Ec::FulfillmentBusinessStatus.resolve(
          platform: fulfillment.platform,
          status: fulfillment.status,
          source_status: fulfillment.source_status,
          source_substatus: fulfillment.source_substatus,
          stats_evidence: stats_evidence,
          returns: return_inputs,
          dispatched: -> { dispatched? }
        )
      end

      def persist(result)
        unless fulfillment.business_status == result.business_status &&
            fulfillment.return_business_status == result.return_business_status
          fulfillment.update_columns(
            business_status: result.business_status, return_business_status: result.return_business_status
          )
        end
        self.class.rollup_order(fulfillment.order)
      end

      def stats_evidence
        return unless fulfillment.platform == "wb"
        return Ec::FulfillmentBusinessStatus::WbStatsEvidence.for_orders([ fulfillment.order_id ])[fulfillment.order_id] if @stats_evidence == :load

        @stats_evidence
      end

      # Returns of the order that belong to this fulfillment: by the order item they were booked against, else by
      # the Ozon posting number, else (an order with a single fulfillment) all returns of the order.
      def return_inputs
        attached_returns.map do |record|
          {
            id: record.id,
            at: record.requested_at || record.created_at,
            source_status: record.source_status,
            process_status: record.process_status,
            returned_to_seller: record.returned_to_seller_at.present?
          }
        end
      end

      def attached_returns
        order_id = fulfillment.order_id
        ids = Ec::ReturnItem.where(order_item_id: fulfillment.items.select(:id)).pluck(:return_id)
        ids += Ec::Return.where(order_id: order_id, external_posting_number: fulfillment.external_fulfillment_id).pluck(:id)
        ids += Ec::Return.where(order_id: order_id).pluck(:id) if Ec::OrderFulfillment.where(order_id: order_id).count == 1
        Ec::Return.where(id: ids.uniq)
      end

      # Evidence that a cancelled fulfillment already left the warehouse.
      def dispatched?
        case fulfillment.platform
        when "wb" then fulfillment.source_substatus == WB_DISPATCHED_SUPPLIER_STATUS || wb_raw_supplier_complete?
        when "ozon" then ozon_handed_to_delivery?
        else false
        end
      end

      def wb_raw_supplier_complete?
        Ec::OrderSourceLink
          .where(order_id: fulfillment.order_id, source_type: "RawWb::Order", source_role: "primary")
          .joins("INNER JOIN raw_wb_orders ON raw_wb_orders.id = ec_order_source_links.source_id")
          .where(raw_wb_orders: { supplier_status: WB_DISPATCHED_SUPPLIER_STATUS })
          .exists?
      end

      def ozon_handed_to_delivery?
        account_id = fulfillment.store.ozon_raw_account_id
        return false if account_id.blank?

        RawOzon::PostingFbs
          .where(account_id: account_id, posting_number: fulfillment.external_fulfillment_id)
          .where.not(delivering_date: nil)
          .exists?
      end
    end
  end
end
```

- [ ] **Step 5: 运行测试确认通过**

```bash
bin/rails test test/services/ec/fulfillment_business_status/updater_test.rb test/services/ec/fulfillment_business_status_test.rb
```

Expected: 全部通过，0 failures。

- [ ] **Step 6: 提交**

```bash
git add app/services/ec/fulfillment_business_status/ test/services/ec/fulfillment_business_status/
git commit -m "feat: add fulfillment business status updater and WB statistics evidence

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 5: 接入订单导入与退货同步

**Files:**
- Modify: `app/services/ec/order_import/ozon.rb`（`import_posting`）
- Modify: `app/services/ec/order_import/wb.rb`（`import_order`、`import_stats_order`、`update_linked_status`）
- Modify: `app/services/ec/returns/base_normalizer.rb`（`call`）
- Test: `test/services/ec/order_import_test.rb`（追加）、`test/services/ec/returns/sync_test.rb`（追加）

**Interfaces:**
- Consumes: `Ec::FulfillmentBusinessStatus::Updater.call(fulfillment)`、`.for_order(order)`（Task 4）

- [ ] **Step 1: 写失败的测试**

在 `test/services/ec/order_import_test.rb` 里，参照该文件已有的 Ozon FBS 导入测试（用 `@ozon_fbs` 这个 posting 夹具），追加：

```ruby
    test "imported Ozon FBS fulfillments get business statuses" do
      Ec::OrderImport::Ozon.new.call

      fulfillment = Ec::OrderFulfillment.find_by!(
        platform: "ozon", store: @ozon_store, external_fulfillment_id: @ozon_fbs.posting_number
      )

      # The fixture posting is `delivering` / `posting_on_way_to_city` and has no return.
      assert_equal "in_delivery", fulfillment.business_status
      assert_equal "none", fulfillment.return_business_status
      assert_equal "in_delivery", fulfillment.order.business_status
    end
```

在 `test/services/ec/returns/sync_test.rb` 的 `SyncTest` 里追加（该文件的 `@ozon_order` 是 `delivered` 订单、`@ozon_order_item` 无 fulfillment，需要先给订单建一个发货单）：

```ruby
      test "syncing a seller received return refreshes the fulfillment business status" do
        fulfillment = @ozon_order.fulfillments.create!(
          platform: "ozon", store: @ozon_store, external_fulfillment_id: @ozon_order.external_order_number,
          fulfillment_key: "ozon:#{@ozon_store.id}:#{@ozon_order.external_order_number}",
          fulfillment_type: "fbs", status: "delivered", source_status: "delivered",
          source_substatus: "posting_received"
        )
        @ozon_order_item.update!(fulfillment: fulfillment)
        @ozon_return.update!(raw_json: { "visual" => { "status" => { "sys_name" => "ReceivedBySeller" } } })

        Ec::Returns::Sync.call(raw_records: [ @ozon_return ])

        fulfillment.reload
        assert_equal "delivered", fulfillment.business_status
        assert_equal "received_by_seller", fulfillment.return_business_status
        assert_equal "received_by_seller", @ozon_order.reload.return_business_status
      ensure
        # Release the item and drop the fulfillment before teardown deletes the order (foreign keys).
        Ec::OrderItem.where(order_id: @ozon_order&.id).update_all(fulfillment_id: nil)
        Ec::OrderFulfillment.where(order_id: @ozon_order&.id).delete_all
      end
```

- [ ] **Step 2: 运行测试确认失败**

```bash
bin/rails test test/services/ec/order_import_test.rb -n "/business statuses/" test/services/ec/returns/sync_test.rb -n "/business status/"
```

Expected: FAIL（`business_status` 仍是默认值 `needs_review`／`none`）。

- [ ] **Step 3: 接入 Ozon 导入**

`app/services/ec/order_import/ozon.rb` 的 `import_posting` 改为：

```ruby
      def import_posting(posting, type, source_type)
        store = store_for(posting.account)
        return 0 unless store

        order = upsert_order(posting, store, type)
        fulfillment = upsert_fulfillment(posting, store, order, type, source_type)
        import_items(posting, store, order, fulfillment, type)
        upsert_source_link(order, fulfillment, nil, source_type, posting.id, posting.posting_number)
        Ec::FulfillmentBusinessStatus::Updater.call(fulfillment)
        1
      end
```

- [ ] **Step 4: 接入 WB 导入**

`app/services/ec/order_import/wb.rb`：

`import_order` 末尾（`upsert_source_link` 之后、`1` 之前）加 `Ec::FulfillmentBusinessStatus::Updater.call(fulfillment)`：

```ruby
      def import_order(raw_order)
        store = store_for(raw_order.account)
        return 0 unless store

        order = upsert_order(raw_order, store)
        fulfillment = upsert_fulfillment(raw_order, store, order)
        import_item(raw_order, store, order, fulfillment)
        upsert_source_link(order, fulfillment, raw_order)
        Ec::FulfillmentBusinessStatus::Updater.call(fulfillment)
        1
      end
```

`import_stats_order` 同样：

```ruby
      def import_stats_order(stats_order)
        store = store_for(stats_order.account)
        return 0 unless store

        order = upsert_order_from_stats(stats_order, store)
        fulfillment = upsert_fulfillment_from_stats(stats_order, store, order)
        import_item_from_stats(stats_order, store, order, fulfillment)
        upsert_stats_source_link(order, fulfillment, stats_order)
        Ec::FulfillmentBusinessStatus::Updater.call(fulfillment)
        1
      end
```

`update_linked_status`（`repair_statuses` 使用）末尾加重算：

```ruby
      def update_linked_status(link, status, source_status, source_substatus)
        attributes = {
          source_status: source_status,
          source_substatus: source_substatus,
          synced_at: Time.current
        }
        link.order.update!(attributes.merge(order_status: status))
        link.fulfillment&.update!(attributes.merge(status: status))
        Ec::FulfillmentBusinessStatus::Updater.call(link.fulfillment) if link.fulfillment
      end
```

- [ ] **Step 5: 接入退货同步**

`app/services/ec/returns/base_normalizer.rb` 的 `call` 改为：

```ruby
      def call
        normalized_return = ApplicationRecord.transaction do
          normalized_return = Ec::Return.find_or_initialize_by(
            platform: platform,
            store: store,
            return_key: return_key
          )
          normalized_return.assign_attributes(return_attributes)
          normalized_return.save!

          item = normalized_return.items.find_or_initialize_by(item_key: item_key)
          item.assign_attributes(item_attributes)
          item.save!

          source_link = Ec::ReturnSourceLink.find_or_initialize_by(
            source_type: raw_record.class.name,
            source_id: raw_record.id
          )
          source_link.assign_attributes(
            return: normalized_return,
            item: item,
            platform: platform,
            source_key: return_key,
            synced_at: raw_record.synced_at
          )
          source_link.save!

          normalized_return
        end

        refresh_fulfillment_business_status(normalized_return)
        normalized_return
      end
```

并在 `private` 区加：

```ruby
      # The return changes where the goods of its order are; refresh every fulfillment of that order.
      def refresh_fulfillment_business_status(normalized_return)
        order = normalized_return.order
        return unless order

        Ec::FulfillmentBusinessStatus::Updater.for_order(order)
      end
```

- [ ] **Step 6: 运行测试确认通过，并跑相关既有测试**

```bash
bin/rails test test/services/ec/order_import_test.rb test/services/ec/returns/sync_test.rb \
  test/services/ec/order_import/wb_stats_only_backfill_test.rb test/services/ec/order_import_wb_price_backfill_test.rb
```

Expected: 新测试通过；既有测试不应因本次改动新增失败。若有既有失败，先 `git stash` 对照确认是否本次引入（该仓库有既有无关失败）。

- [ ] **Step 7: 提交**

```bash
git add app/services/ec/order_import/ozon.rb app/services/ec/order_import/wb.rb \
  app/services/ec/returns/base_normalizer.rb \
  test/services/ec/order_import_test.rb test/services/ec/returns/sync_test.rb
git commit -m "feat: refresh fulfillment business status on order import and return sync

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 6: 回填与一致性检查

**Files:**
- Create: `app/services/ec/fulfillment_business_status/backfill.rb`
- Create: `script/backfill_fulfillment_business_status.rb`
- Test: `test/services/ec/fulfillment_business_status/backfill_test.rb`

**Interfaces:**
- Consumes: `Updater.call(fulfillment, stats_evidence:, write:)`、`Updater.rollup_order`、`WbStatsEvidence.for_orders`（Task 4）
- Produces: `Ec::FulfillmentBusinessStatus::Backfill.run(dry_run: false, batch_size: 500, platform: nil, store_ids: nil)` → `{ checked: Integer, changed: Integer, samples: Array<Hash> }`；`samples` 最多 20 条 `{ fulfillment_id:, from: [..], to: [..] }`；`platform`／`store_ids` 用来限定范围（测试里限定到自己创建的店铺）

- [ ] **Step 1: 写失败的测试**

创建 `test/services/ec/fulfillment_business_status/backfill_test.rb`：

```ruby
require "test_helper"
require_relative "../../../support/book_ledger_fixtures"

class Ec::FulfillmentBusinessStatus::BackfillTest < ActiveSupport::TestCase
  include BookLedgerFixtures

  setup { setup_ledger_world }
  teardown { teardown_ledger_world }

  def scoped_run(**options)
    Ec::FulfillmentBusinessStatus::Backfill.run(
      store_ids: [ @wb_store.id, @ozon_store.id ], **options
    )
  end

  test "dry run reports differences without writing" do
    order = ledger_order(platform: "ozon", status: "delivered", source_status: "delivered",
      source_substatus: "posting_received")

    result = scoped_run(dry_run: true)

    assert_equal 1, result[:checked]
    assert_equal 1, result[:changed]
    assert_equal [ "needs_review", "none" ], result[:samples].first[:from]
    assert_equal [ "delivered", "none" ], result[:samples].first[:to]
    assert_equal "needs_review", order.fulfillments.first.reload.business_status
  end

  test "backfill writes statuses and is idempotent" do
    order = ledger_order(platform: "wb", status: "delivered", source_status: "sold", source_substatus: "complete")
    ledger_order(platform: "ozon", status: "processing", source_status: "awaiting_packaging",
      source_substatus: "posting_created")

    first = scoped_run
    second = scoped_run

    assert_equal 2, first[:changed]
    assert_equal 0, second[:changed]
    assert_equal "delivered", order.fulfillments.first.reload.business_status
    assert_equal "delivered", order.reload.business_status
  end
end
```

- [ ] **Step 2: 运行测试确认失败**

```bash
bin/rails test test/services/ec/fulfillment_business_status/backfill_test.rb
```

Expected: ERROR，`uninitialized constant ...::Backfill`。

- [ ] **Step 3: 实现回填**

创建 `app/services/ec/fulfillment_business_status/backfill.rb`：

```ruby
module Ec
  module FulfillmentBusinessStatus
    # Recomputes both statuses for existing fulfillments. Idempotent. With dry_run: true it only reports the
    # differences, which makes it the consistency check between stored and computed values.
    class Backfill
      SAMPLE_LIMIT = 20

      def self.run(dry_run: false, batch_size: 500, platform: nil, store_ids: nil)
        new(dry_run: dry_run, batch_size: batch_size, platform: platform, store_ids: store_ids).run
      end

      def initialize(dry_run:, batch_size:, platform:, store_ids:)
        @dry_run = dry_run
        @batch_size = batch_size
        @platform = platform
        @store_ids = store_ids
      end

      def run
        result = { checked: 0, changed: 0, samples: [] }
        touched_order_ids = []

        scope.includes(:store).find_in_batches(batch_size: @batch_size) do |batch|
          evidence = Ec::FulfillmentBusinessStatus::WbStatsEvidence.for_orders(
            batch.select { |fulfillment| fulfillment.platform == "wb" }.map(&:order_id)
          )
          batch.each do |fulfillment|
            before = [ fulfillment.business_status, fulfillment.return_business_status ]
            computed = Ec::FulfillmentBusinessStatus::Updater.call(
              fulfillment, stats_evidence: evidence[fulfillment.order_id], write: false
            )
            after = [ computed.business_status, computed.return_business_status ]
            result[:checked] += 1
            next if before == after

            result[:changed] += 1
            if result[:samples].size < SAMPLE_LIMIT
              result[:samples] << { fulfillment_id: fulfillment.id, from: before, to: after }
            end
            next if @dry_run

            fulfillment.update_columns(business_status: after.first, return_business_status: after.last)
            touched_order_ids << fulfillment.order_id
          end
        end

        roll_up(touched_order_ids.uniq) unless @dry_run
        result
      end

      private

      def scope
        relation = Ec::OrderFulfillment.all
        relation = relation.where(platform: @platform) if @platform
        relation = relation.where(store_id: @store_ids) if @store_ids
        relation
      end

      def roll_up(order_ids)
        order_ids.each_slice(@batch_size) do |ids|
          Ec::Order.where(id: ids).find_each { |order| Ec::FulfillmentBusinessStatus::Updater.rollup_order(order) }
        end
      end
    end
  end
end
```

注意：`Updater.call(..., write: false)` 内部的 `stats_evidence` 对非 WB 返回 `nil`、对 WB 使用调用方传入值，不会再逐条查库；`return_inputs` 和 `dispatched?` 仍是逐条查询，236 个 SKU 对应的约 2.3 万条发货单预计在几分钟内完成。

- [ ] **Step 4: 回填脚本入口**

创建 `script/backfill_fulfillment_business_status.rb`：

```ruby
# Recomputes the business statuses of every fulfillment.
#
#   bin/rails runner script/backfill_fulfillment_business_status.rb --dry-run
#   bin/rails runner script/backfill_fulfillment_business_status.rb
#   bin/rails runner script/backfill_fulfillment_business_status.rb --platform=wb
#
# --dry-run only reports how many fulfillments differ from the stored values (a consistency check).
dry_run = ARGV.include?("--dry-run")
platform = ARGV.filter_map { |argument| argument.delete_prefix("--platform=") if argument.start_with?("--platform=") }.first

result = Ec::FulfillmentBusinessStatus::Backfill.run(dry_run: dry_run, platform: platform)
puts "checked=#{result[:checked]} changed=#{result[:changed]} dry_run=#{dry_run}"
result[:samples].each do |sample|
  puts "  fulfillment #{sample[:fulfillment_id]}: #{sample[:from].join(' / ')} -> #{sample[:to].join(' / ')}"
end
```

- [ ] **Step 5: 运行测试确认通过**

```bash
bin/rails test test/services/ec/fulfillment_business_status/backfill_test.rb
```

Expected: 2 runs, 0 failures。

- [ ] **Step 6: 在本地开发库回填并检查分布**

```bash
bin/rails runner script/backfill_fulfillment_business_status.rb --dry-run | head -5
bin/rails runner script/backfill_fulfillment_business_status.rb
bin/rails runner script/backfill_fulfillment_business_status.rb --dry-run | head -3
```

Expected: 第一次 dry run 的 `changed` 约等于全部发货单数（22911 左右）；第二次回填结束；第三次 dry run 输出 `changed=0`（幂等）。

然后看 FBS 的分布是否与设计一致：

```bash
bin/rails runner '
rows = Ec::OrderFulfillment.where(fulfillment_type: "fbs")
  .group(:business_status, :return_business_status).count
rows.sort.each { |(business, ret), count| puts "#{business} | #{ret} => #{count}" }
'
```

Expected: 出现的组合集中在设计矩阵里；"待装配 × 卖家已收"（约 10 个 SKU 的 29 个单位）和"配送中 × 在平台侧"（2 个单位）是已知异常。

- [ ] **Step 7: 提交**

```bash
git add app/services/ec/fulfillment_business_status/backfill.rb \
  script/backfill_fulfillment_business_status.rb \
  test/services/ec/fulfillment_business_status/backfill_test.rb
git commit -m "feat: add fulfillment business status backfill and consistency check

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 7: 交叉表查询与订单明细查询

**Files:**
- Create: `app/services/ec/inventory_fbs_status_matrix_query.rb`
- Create: `app/services/ec/inventory_fbs_orders_query.rb`
- Test: `test/services/ec/inventory_fbs_status_matrix_query_test.rb`、`test/services/ec/inventory_fbs_orders_query_test.rb`

**Interfaces:**
- Consumes: 新列（Task 3），`ORDER_ITEM_JOIN`
- Produces:
  - `Ec::InventoryFbsStatusMatrixQuery.new(sku).call` → `{ cells: Array<Hash>, summary: Hash }`
    - cell：`{ business_status:, return_business_status:, quantity:, kind:, anomaly: }`，`kind` 为 `"not_left"`｜`"left"`｜`"returned"`
    - summary：`{ departed_quantity:, not_departed_quantity:, returned_quantity:, anomaly_quantity:, total_quantity: }`；`departed_quantity` 含已回仓（`left` + `returned`）
  - `Ec::InventoryFbsStatusMatrixQuery.kind(business_status, return_business_status)` → `"not_left"`｜`"left"`｜`"returned"`
  - `Ec::InventoryFbsStatusMatrixQuery.anomaly?(business_status, return_business_status)` → Boolean
  - `Ec::InventoryFbsOrdersQuery.new(sku, business_status:, return_business_status:, page: 1).call` → `{ rows: Array<Hash>, pagination: { page:, per_page:, total_count:, total_pages: } }`
    - row：`{ platform:, store_name:, order_number:, fulfillment_number:, ordered_at:, business_status:, return_business_status:, source_status_label:, quantity: }`

- [ ] **Step 1: 写失败的测试**

创建 `test/services/ec/inventory_fbs_status_matrix_query_test.rb`：

```ruby
require "test_helper"
require_relative "../../support/book_ledger_fixtures"

class Ec::InventoryFbsStatusMatrixQueryTest < ActiveSupport::TestCase
  include BookLedgerFixtures

  setup { setup_ledger_world }
  teardown { teardown_ledger_world }

  def fbs_fulfillment(platform:, business_status:, return_business_status: "none", quantity: 1, fulfillment_type: "fbs")
    order = ledger_order(platform: platform, status: "delivered", quantity: quantity, fulfillment_type: fulfillment_type)
    order.fulfillments.first.update_columns(
      business_status: business_status, return_business_status: return_business_status
    )
    order
  end

  test "kind classifies a cell by whether the goods left the warehouse and came back" do
    kind = ->(business, ret) { Ec::InventoryFbsStatusMatrixQuery.kind(business, ret) }

    assert_equal "not_left", kind.call("awaiting_assembly", "none")
    assert_equal "not_left", kind.call("awaiting_dispatch", "none")
    assert_equal "not_left", kind.call("needs_review", "none")
    assert_equal "not_left", kind.call("cancelled", "none")
    assert_equal "left", kind.call("in_delivery", "none")
    assert_equal "left", kind.call("delivered", "none")
    assert_equal "left", kind.call("cancelled", "expected")
    assert_equal "left", kind.call("cancelled", "at_platform_side")
    assert_equal "left", kind.call("delivered", "no_physical_return")
    assert_equal "returned", kind.call("delivered", "received_by_seller")
    assert_equal "returned", kind.call("cancelled", "received_by_seller")
    assert_equal "returned", kind.call("awaiting_assembly", "received_by_seller")
  end

  test "anomaly marks combinations that should not occur" do
    anomaly = ->(business, ret) { Ec::InventoryFbsStatusMatrixQuery.anomaly?(business, ret) }

    assert_not anomaly.call("delivered", "received_by_seller")
    assert_not anomaly.call("cancelled", "expected")
    assert anomaly.call("awaiting_assembly", "received_by_seller")
    assert anomaly.call("in_delivery", "at_platform_side")
    assert anomaly.call("delivered", "expected")
  end

  test "sums FBS order item quantities per cell for the sku only" do
    fbs_fulfillment(platform: "wb", business_status: "delivered", quantity: 5)
    fbs_fulfillment(platform: "ozon", business_status: "delivered", quantity: 2)
    fbs_fulfillment(platform: "wb", business_status: "awaiting_assembly", quantity: 3)
    fbs_fulfillment(platform: "wb", business_status: "cancelled", return_business_status: "received_by_seller", quantity: 4)
    fbs_fulfillment(platform: "wb", business_status: "awaiting_assembly", return_business_status: "received_by_seller")
    fbs_fulfillment(platform: "ozon", business_status: "delivered", fulfillment_type: "fbo", quantity: 9)

    result = Ec::InventoryFbsStatusMatrixQuery.new(@sku).call
    cells = result[:cells].to_h { |cell| [ [ cell[:business_status], cell[:return_business_status] ], cell ] }

    assert_equal 7, cells.fetch([ "delivered", "none" ])[:quantity]
    assert_equal "left", cells.fetch([ "delivered", "none" ])[:kind]
    assert_equal 3, cells.fetch([ "awaiting_assembly", "none" ])[:quantity]
    assert_equal 4, cells.fetch([ "cancelled", "received_by_seller" ])[:quantity]
    assert cells.fetch([ "awaiting_assembly", "received_by_seller" ])[:anomaly]
    assert_equal(
      { departed_quantity: 12, not_departed_quantity: 3, returned_quantity: 5, anomaly_quantity: 1, total_quantity: 15 },
      result[:summary]
    )
  end

  test "ignores order items that are not linked to the sku through sku products" do
    order = fbs_fulfillment(platform: "wb", business_status: "delivered", quantity: 6)
    order.items.update_all(platform_sku_id: "UNBOUND-#{@token}", sku_code: @sku.sku_code)

    result = Ec::InventoryFbsStatusMatrixQuery.new(@sku).call

    assert_equal 0, result.dig(:summary, :total_quantity)
  end
end
```

创建 `test/services/ec/inventory_fbs_orders_query_test.rb`：

```ruby
require "test_helper"
require_relative "../../support/book_ledger_fixtures"

class Ec::InventoryFbsOrdersQueryTest < ActiveSupport::TestCase
  include BookLedgerFixtures

  setup { setup_ledger_world }
  teardown { teardown_ledger_world }

  def fbs_order(business_status:, return_business_status: "none", quantity: 1, ordered_at: Time.current - 5.days)
    order = ledger_order(platform: "wb", status: "delivered", quantity: quantity, ordered_at: ordered_at,
      source_status: "sold", source_substatus: "complete")
    order.fulfillments.first.update_columns(
      business_status: business_status, return_business_status: return_business_status
    )
    order
  end

  test "lists the orders of one cell, newest first, with pagination" do
    older = fbs_order(business_status: "delivered", ordered_at: 3.days.ago)
    newer = fbs_order(business_status: "delivered", ordered_at: 1.day.ago, quantity: 2)
    fbs_order(business_status: "cancelled")

    result = Ec::InventoryFbsOrdersQuery.new(
      @sku, business_status: "delivered", return_business_status: "none", page: 1
    ).call

    assert_equal [ newer.external_order_id, older.external_order_id ],
      result[:rows].map { |row| row[:fulfillment_number] }
    assert_equal [ 2, 1 ], result[:rows].map { |row| row[:quantity] }
    assert_equal "wb", result[:rows].first[:platform]
    assert_equal @wb_store.store_name, result[:rows].first[:store_name]
    assert_equal({ page: 1, per_page: 20, total_count: 2, total_pages: 1 }, result[:pagination])
  end

  test "paginates and clamps the page" do
    21.times { fbs_order(business_status: "delivered") }

    second = Ec::InventoryFbsOrdersQuery.new(
      @sku, business_status: "delivered", return_business_status: "none", page: 2
    ).call
    clamped = Ec::InventoryFbsOrdersQuery.new(
      @sku, business_status: "delivered", return_business_status: "none", page: 99
    ).call

    assert_equal 1, second[:rows].size
    assert_equal 21, second.dig(:pagination, :total_count)
    assert_equal 2, clamped.dig(:pagination, :page)
  end
end
```

注意：`ledger_order` 里 `external_fulfillment_id` 就是 `key`（同时赋给了订单的 `external_order_id`），所以上面用 `order.external_order_id` 与 `fulfillment_number` 对比。

- [ ] **Step 2: 运行测试确认失败**

```bash
bin/rails test test/services/ec/inventory_fbs_status_matrix_query_test.rb test/services/ec/inventory_fbs_orders_query_test.rb
```

Expected: ERROR，`uninitialized constant Ec::InventoryFbsStatusMatrixQuery`。

- [ ] **Step 3: 实现交叉表查询**

创建 `app/services/ec/inventory_fbs_status_matrix_query.rb`：

```ruby
module Ec
  # Physical stocktake view of one SKU's FBS fulfillments: quantity per (business status x return business status).
  # Order items are attributed to the SKU only through the hard ec_sku_products link.
  class InventoryFbsStatusMatrixQuery
    ORDER_ITEM_JOIN = SalesFunnelReports::SkuFunnelAnalysisQuery::ORDER_ITEM_JOIN
    NOT_LEFT_BUSINESS_STATUSES = %w[awaiting_assembly awaiting_dispatch needs_review cancelled].freeze
    EXPECTED_RETURN_STATUSES = {
      "awaiting_assembly" => %w[none],
      "awaiting_dispatch" => %w[none],
      "needs_review" => %w[none],
      "in_delivery" => %w[none],
      "delivered" => %w[none at_platform_side returning_to_seller received_by_seller no_physical_return],
      "cancelled" => %w[none expected at_platform_side returning_to_seller received_by_seller no_physical_return]
    }.freeze

    # not_left: still in the seller warehouse; left: left the warehouse; returned: left and came back.
    def self.kind(business_status, return_business_status)
      return "returned" if return_business_status == "received_by_seller"
      if return_business_status == "none" && business_status.in?(NOT_LEFT_BUSINESS_STATUSES)
        return "not_left"
      end

      "left"
    end

    def self.anomaly?(business_status, return_business_status)
      !EXPECTED_RETURN_STATUSES.fetch(business_status, []).include?(return_business_status)
    end

    def initialize(sku)
      @sku = sku
    end

    def call
      cells = quantities.map do |(business_status, return_business_status), quantity|
        {
          business_status: business_status,
          return_business_status: return_business_status,
          quantity: quantity.to_i,
          kind: self.class.kind(business_status, return_business_status),
          anomaly: self.class.anomaly?(business_status, return_business_status)
        }
      end
      cells.sort_by! do |cell|
        [
          Ec::FulfillmentBusinessStatus::BUSINESS_STATUSES.index(cell[:business_status]).to_i,
          Ec::FulfillmentBusinessStatus::RETURN_STATUSES.index(cell[:return_business_status]).to_i
        ]
      end

      { cells: cells, summary: summary(cells) }
    end

    private

    def quantities
      Ec::OrderItem
        .joins(:fulfillment)
        .joins(ORDER_ITEM_JOIN)
        .where(ec_sku_products: { sku_code: @sku.sku_code })
        .where(ec_order_fulfillments: { fulfillment_type: "fbs" })
        .group("ec_order_fulfillments.business_status", "ec_order_fulfillments.return_business_status")
        .sum("ec_order_items.quantity")
    end

    def summary(cells)
      by_kind = cells.group_by { |cell| cell[:kind] }.transform_values { |list| list.sum { |cell| cell[:quantity] } }
      {
        departed_quantity: by_kind.fetch("left", 0) + by_kind.fetch("returned", 0),
        not_departed_quantity: by_kind.fetch("not_left", 0),
        returned_quantity: by_kind.fetch("returned", 0),
        anomaly_quantity: cells.select { |cell| cell[:anomaly] }.sum { |cell| cell[:quantity] },
        total_quantity: cells.sum { |cell| cell[:quantity] }
      }
    end
  end
end
```

- [ ] **Step 4: 实现订单明细查询**

创建 `app/services/ec/inventory_fbs_orders_query.rb`：

```ruby
module Ec
  # Orders behind one cell of the FBS status matrix of a SKU.
  class InventoryFbsOrdersQuery
    PAGE_SIZE = 20
    ORDER_ITEM_JOIN = Ec::InventoryFbsStatusMatrixQuery::ORDER_ITEM_JOIN

    def initialize(sku, business_status:, return_business_status:, page: 1)
      @sku = sku
      @business_status = business_status
      @return_business_status = return_business_status
      @requested_page = [ page.to_i, 1 ].max
    end

    def call
      total_count = scope.count
      total_pages = [ (total_count / PAGE_SIZE.to_f).ceil, 1 ].max
      page = [ @requested_page, total_pages ].min
      labeler = Ec::InventoryOrderSalesDistributionQuery.new(@sku)

      rows = scope
        .order(Arel.sql("ec_orders.ordered_at DESC NULLS LAST"), Arel.sql("ec_order_items.id DESC"))
        .offset((page - 1) * PAGE_SIZE).limit(PAGE_SIZE)
        .pluck(
          "ec_order_items.platform", "ec_stores.store_name", "ec_orders.external_order_number",
          "ec_order_fulfillments.external_fulfillment_id", "ec_orders.ordered_at",
          "ec_order_fulfillments.source_status", "ec_order_fulfillments.source_substatus",
          "ec_order_items.quantity"
        ).map do |platform, store_name, order_number, fulfillment_number, ordered_at, source_status, source_substatus, quantity|
          {
            platform: platform,
            store_name: store_name,
            order_number: order_number,
            fulfillment_number: fulfillment_number,
            ordered_at: ordered_at,
            business_status: @business_status,
            return_business_status: @return_business_status,
            source_status_label: labeler.source_status_label(platform, source_status, source_substatus),
            quantity: quantity.to_i
          }
        end

      {
        rows: rows,
        pagination: { page: page, per_page: PAGE_SIZE, total_count: total_count, total_pages: total_pages }
      }
    end

    private

    def scope
      @scope ||= Ec::OrderItem
        .joins(:fulfillment, :order, :store)
        .joins(ORDER_ITEM_JOIN)
        .where(ec_sku_products: { sku_code: @sku.sku_code })
        .where(ec_order_fulfillments: {
          fulfillment_type: "fbs", business_status: @business_status,
          return_business_status: @return_business_status
        })
    end
  end
end
```

- [ ] **Step 5: 运行测试确认通过**

```bash
bin/rails test test/services/ec/inventory_fbs_status_matrix_query_test.rb test/services/ec/inventory_fbs_orders_query_test.rb
```

Expected: 全部通过。若 `ledger_order` 创建的 `external_order_number` 为空，行里的 `order_number` 会是 `nil`，页面用 `report_value` 展示 `-`，不影响。

- [ ] **Step 6: 提交**

```bash
git add app/services/ec/inventory_fbs_status_matrix_query.rb app/services/ec/inventory_fbs_orders_query.rb \
  test/services/ec/inventory_fbs_status_matrix_query_test.rb test/services/ec/inventory_fbs_orders_query_test.rb
git commit -m "feat: add FBS business status matrix and order list queries

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 8: 盘库查询改读交叉表

**Files:**
- Modify: `app/services/ec/inventory_physical_reconciliation_query.rb`
- Modify: `app/services/ec/inventory_page_row_query.rb`（`expected_physical_stock`）
- Modify: `app/services/ec/inventory_page_detail_query.rb`（`physical_reconciliation`）
- Modify: `test/services/ec/inventory_physical_reconciliation_query_test.rb`
- Modify: `test/services/ec/inventory_page_row_query_test.rb`（如其中传了 `order_distribution`，同步调整）

**Interfaces:**
- Consumes: `Ec::InventoryFbsStatusMatrixQuery`（Task 7）
- Produces: `Ec::InventoryPhysicalReconciliationQuery.new(sku, overview:, supply_page: nil, return_filters: nil, return_page: nil)`（**不再接收 `order_distribution:`**）；`#call` 返回里的 `:fbs_order_rows` 换成 `:fbs_matrix`（`InventoryFbsStatusMatrixQuery#call` 的返回值），`summary` 键不变：
  - `fbs_departed_quantity` = `fbs_matrix[:summary][:departed_quantity]`（已离仓，含已回仓）
  - `fbs_not_departed_quantity` = `fbs_matrix[:summary][:not_departed_quantity]`
  - `fbs_order_quantity` = `fbs_matrix[:summary][:total_quantity]`
  - 其余键（送仓、退货、移出、`expected_physical_stock`）含义与公式结构不变

- [ ] **Step 1: 先看现有测试里哪些依赖旧结构**

```bash
grep -n "order_distribution\|fbs_order_rows\|physical_deducted\|create_cancelled" test/services/ec/inventory_physical_reconciliation_query_test.rb
grep -rn "order_distribution:" test app | grep -v "^test/services/ec/inventory_physical_reconciliation_query_test.rb"
```

记下每个出现位置。依赖旧结构的测试分三类处理：

1. 只用 `order_distribution: { rows: [] }` 的（物理盘库矫正、WB FBW 退货等）：去掉这个入参即可，断言不变。
2. 用 `order_distribution` 注入已发货订单数量的（"builds expected physical stock..."）：改成创建对应数量的 FBS 发货单（见 Step 2 的辅助方法），断言的数字保持不变。
3. 专门测旧阶段与合成取消阶段的（"counts FBS orders cancelled after dispatch..."、"deducts WB FBS orders cancelled..."、"groups FBS rows by platform..."、"splits Ozon FBS rows..."）：这些逻辑已由解析器测试（Task 2/4）和交叉表测试（Task 7）覆盖，整条删除，并用 Step 2 的两个新测试替换。

- [ ] **Step 2: 写失败的测试**

在 `test/services/ec/inventory_physical_reconciliation_query_test.rb` 的私有方法区加辅助方法：

```ruby
  def create_fbs_fulfillment(platform:, business_status:, return_business_status: "none", quantity: 1)
    store = platform == "wb" ? @wb_store : @ozon_store
    product_id = platform == "wb" ? @wb_product.product_id : @ozon_product.platform_sku_id
    key = "FBS-#{platform}-#{SecureRandom.hex(5)}"
    order = Ec::Order.create!(
      platform: platform, store: store, order_key: key, external_order_id: key, order_status: "delivered"
    )
    fulfillment = order.fulfillments.create!(
      platform: platform, store: store, external_fulfillment_id: key, fulfillment_key: key,
      fulfillment_type: "fbs", status: "delivered", business_status: business_status,
      return_business_status: return_business_status
    )
    Ec::OrderItem.create!(
      platform: platform, store: store, order: order, fulfillment: fulfillment, external_item_id: key,
      platform_sku_id: product_id, sku_code: @sku.sku_code, quantity: quantity
    )
  end
```

把 "builds expected physical stock and keeps returns removals and supplies as separate flows" 里给 `order_distribution` 赋值的那个 hash（含两行：`status_key: "delivered_confirmed"` 数量 9、`status_key: "awaiting_preparation"` 数量 3）整段删掉，换成下面两行创建数据（保持原来的 9 个离仓、3 个未离仓）：

```ruby
    create_fbs_fulfillment(platform: "ozon", business_status: "delivered", quantity: 9)
    create_fbs_fulfillment(platform: "ozon", business_status: "awaiting_assembly", quantity: 3)
```

并把 `.new(@sku, overview:, order_distribution:, ...)` 里的 `order_distribution:` 入参全部删掉，把对应断言

```ruby
    assert_equal [ [ 9, true ], [ 3, false ] ],
      result[:fbs_order_rows].map { |row| [ row[:quantity], row[:physical_deducted] ] }
```

替换为：

```ruby
    assert_equal [ [ "awaiting_assembly", "none", 3, "not_left" ], [ "delivered", "none", 9, "left" ] ],
      result.dig(:fbs_matrix, :cells).map do |cell|
        [ cell[:business_status], cell[:return_business_status], cell[:quantity], cell[:kind] ]
      end
```

再追加两个新测试（替换第 3 类被删的测试）：

```ruby
  test "FBS departures come from the business status matrix and seller received returns are added back" do
    create_fbs_fulfillment(platform: "wb", business_status: "delivered", quantity: 10)
    create_fbs_fulfillment(platform: "wb", business_status: "cancelled", return_business_status: "received_by_seller", quantity: 2)
    create_fbs_fulfillment(platform: "ozon", business_status: "cancelled", return_business_status: "expected", quantity: 3)
    create_fbs_fulfillment(platform: "ozon", business_status: "cancelled", quantity: 4)
    create_fbs_fulfillment(platform: "wb", business_status: "awaiting_assembly", quantity: 5)
    return_record = Ec::Return.create!(
      platform: "wb", store: @wb_store, return_key: "WB-ADDBACK-#{@token}", return_type: "cancellation_return",
      process_status: "completed", source_status: "Выдано", returned_to_seller_at: Time.current,
      external_return_id: "WB-ADDBACK-#{@token}"
    )
    return_record.items.create!(
      platform: "wb", store: @wb_store, sku_product: @wb_product, item_key: "WB-ADDBACK-ITEM-#{@token}",
      quantity: 2, restockable: true
    )

    result = Ec::InventoryPhysicalReconciliationQuery.new(
      @sku, overview: { summary: { received_quantity: 30 } }
    ).call

    # departed: 10 delivered + 2 cancelled and returned + 3 cancelled and expected back
    assert_equal 15, result.dig(:summary, :fbs_departed_quantity)
    assert_equal 9, result.dig(:summary, :fbs_not_departed_quantity)
    assert_equal 24, result.dig(:summary, :fbs_order_quantity)
    assert_equal 2, result.dig(:summary, :seller_received_return_quantity)
    assert_equal 17, result.dig(:summary, :expected_physical_stock)
  end

  test "a seller received return proves the goods left even when the order looks unshipped" do
    create_fbs_fulfillment(platform: "wb", business_status: "awaiting_assembly", return_business_status: "received_by_seller")
    return_record = Ec::Return.create!(
      platform: "wb", store: @wb_store, return_key: "WB-STUCK-#{@token}", return_type: "customer_return",
      process_status: "completed", source_status: "Выдано", returned_to_seller_at: Time.current,
      external_return_id: "WB-STUCK-#{@token}"
    )
    return_record.items.create!(
      platform: "wb", store: @wb_store, sku_product: @wb_product, item_key: "WB-STUCK-ITEM-#{@token}",
      quantity: 1, restockable: true
    )

    result = Ec::InventoryPhysicalReconciliationQuery.new(
      @sku, overview: { summary: { received_quantity: 10 } }
    ).call

    assert_equal 1, result.dig(:summary, :fbs_departed_quantity)
    assert_equal 1, result.dig(:summary, :seller_received_return_quantity)
    # 10 received - 1 departed + 1 returned: the unshipped looking order is not counted twice
    assert_equal 10, result.dig(:summary, :expected_physical_stock)
    assert_equal 1, result.dig(:fbs_matrix, :summary, :anomaly_quantity)
  end
```

- [ ] **Step 3: 运行测试确认失败**

```bash
bin/rails test test/services/ec/inventory_physical_reconciliation_query_test.rb
```

Expected: FAIL／ERROR（`unknown keyword: :order_distribution` 的反向——测试里已经不传，但查询要求必传；以及 `fbs_matrix` 缺失）。

- [ ] **Step 4: 改写查询**

`app/services/ec/inventory_physical_reconciliation_query.rb`：

1. 删除常量 `CANCELLED_RETURNED_STATUS_KEY`、`CANCELLED_DISPATCHED_STATUS_KEY`、`CANCELLED_BEFORE_DISPATCH_STATUS_KEY`、`WB_DISPATCHED_SUPPLIER_STATUS`、`FBS_DEPARTED_STATUS_KEYS`、`FBS_ROW_STATUS_ORDER`、`NO_RETURN_STATE_KEY`、`RETURN_STATE_ORDER`。
2. `initialize` 去掉 `order_distribution:`：

```ruby
    def initialize(sku, overview:, supply_page: nil, return_filters: nil, return_page: nil)
      @sku = sku
      @overview = overview
      @requested_supply_page = [ supply_page.to_i, 1 ].max
      @return_filters = normalize_return_filters(return_filters)
      @requested_return_page = [ return_page.to_i, 1 ].max
    end
```

3. `call` 里把 `fbs_order_rows: fbs_order_rows,` 换成 `fbs_matrix: fbs_matrix,`。
4. `summary` 里：

```ruby
        fbs_departed_quantity = fbs_matrix.dig(:summary, :departed_quantity).to_i
```

并把返回 hash 中的

```ruby
          fbs_not_departed_quantity: fbs_not_departed_rows.sum { |row| row[:quantity].to_i },
          fbs_order_quantity: fbs_order_rows.sum { |row| row[:quantity].to_i },
```

换成

```ruby
          fbs_not_departed_quantity: fbs_matrix.dig(:summary, :not_departed_quantity).to_i,
          fbs_order_quantity: fbs_matrix.dig(:summary, :total_quantity).to_i,
```

5. 删除这些私有方法：`fbs_order_rows`、`split_by_return_state`、`ozon_returns_by_order`、`cancelled_returned_fbs_rows`、`cancelled_unreturned_fbs_rows`、`sku_order_items_scope`、`cancelled_order_items_scope`、`ozon_dispatched_posting_keys`、`wb_dispatched_order_ids`、`cancelled_fbs_rows`、`fbs_departed_rows`、`fbs_not_departed_rows`。
6. 新增：

```ruby
    def fbs_matrix
      @fbs_matrix ||= Ec::InventoryFbsStatusMatrixQuery.new(@sku).call
    end
```

7. 保留不动：`return_items`、`all_return_rows`、`physical_return_included?`、`physical_return_scope?`、送仓、移出相关的全部方法（它们不属于 FBS 订单流转）。
8. 在文件顶部把 `physical_return_scope?` 里依赖的 `return_record.order.fulfillments` 保持原样。

`app/services/ec/inventory_page_row_query.rb` 的 `expected_physical_stock`：

```ruby
    def expected_physical_stock(overview)
      Ec::InventoryPhysicalReconciliationQuery.new(@sku, overview: overview).expected_physical_stock
    end
```

`app/services/ec/inventory_page_detail_query.rb` 的 `physical_reconciliation`：

```ruby
    def physical_reconciliation(overview)
      return unless @detail_tab.in?(%w[overview physical_stocktake])

      Ec::InventoryPhysicalReconciliationQuery.new(
        @sku,
        overview: overview,
        supply_page: @physical_supply_page,
        return_filters: @physical_return_filters,
        return_page: @physical_return_page
      ).call
    end
```

并把调用处 `physical_reconciliation: physical_reconciliation(overview, book_sales_distribution),` 改为 `physical_reconciliation: physical_reconciliation(overview),`（`book_sales_distribution` 本身仍被其他面板使用，保留）。

- [ ] **Step 5: 运行测试确认通过**

```bash
bin/rails test test/services/ec/inventory_physical_reconciliation_query_test.rb test/services/ec/inventory_page_row_query_test.rb
```

Expected: 全部通过。如果 `inventory_page_row_query_test.rb` 里有测试构造了依赖旧阶段的数据，按 Step 1 的三类规则同步调整。

- [ ] **Step 6: 提交**

```bash
git add app/services/ec/inventory_physical_reconciliation_query.rb \
  app/services/ec/inventory_page_row_query.rb app/services/ec/inventory_page_detail_query.rb \
  test/services/ec/inventory_physical_reconciliation_query_test.rb test/services/ec/inventory_page_row_query_test.rb
git commit -m "refactor: derive FBS physical stock from the business status matrix

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 9: 页面——交叉表与订单弹窗

**Files:**
- Create: `config/locales/fulfillment_business_status.zh.yml`、`.en.yml`、`.ru.yml`
- Modify: `config/routes.rb`
- Modify: `app/controllers/reports_controller.rb`
- Modify: `app/views/reports/_inventory_physical_reconciliation.html.erb`
- Create: `app/views/reports/inventory_fbs_orders.html.erb`
- Modify: `app/assets/stylesheets/application.css`
- Test: `test/controllers/reports_controller_test.rb`（追加，并调整已有的 FBS 板块断言）

**Interfaces:**
- Consumes: `Ec::InventoryFbsStatusMatrixQuery`、`Ec::InventoryFbsOrdersQuery`（Task 7），`reconciliation[:fbs_matrix]`（Task 8）
- Produces: 路由 `report_inventory_fbs_orders_path(sku_code, business_status:, return_business_status:, page:)`（`GET /reports/inventory/:sku_code/fbs_orders`）

- [ ] **Step 1: 写文案**

创建 `config/locales/fulfillment_business_status.zh.yml`：

```yaml
zh:
  fulfillment_business_status:
    business:
      awaiting_assembly: 待装配
      awaiting_dispatch: 待发运
      in_delivery: 配送中
      delivered: 已签收
      cancelled: 已取消
      needs_review: 待核实
    return:
      none: 无退货
      expected: 待退回
      at_platform_side: 在平台侧
      returning_to_seller: 返回卖家途中
      received_by_seller: 卖家已收
      no_physical_return: 无实物回流
  reports:
    inventory:
      drawer:
        physical_stocktake:
          fbs_matrix:
            note: 业务状态表示货在发货链路的哪一步，退货状态表示退回的货走到哪里。已离仓的格子从盘库应见库存中扣除，卖家已收的格子随退货加回；未离仓的格子仍在白俄仓。点击数字查看订单。
            row_header: 业务状态 ╲ 退货状态
            kinds:
              not_left: 未离仓
              left: 已离仓
              returned: 已回仓
              anomaly: 状态异常
            legend: 图例
            anomaly_summary: 状态异常（已计入上方数量）
          fbs_orders_modal:
            title: FBS 订单明细
            summary_cell: "%{business} × %{return}"
            quantity: 数量合计
            empty: 当前没有相关订单
            columns:
              platform_store: 平台 / 店铺
              order_number: 订单号
              fulfillment_number: 发货单号
              ordered_at: 下单时间
              source_status: 平台原始状态
              quantity: 数量
            pagination_aria_label: FBS 订单明细分页
```

创建 `config/locales/fulfillment_business_status.en.yml`：

```yaml
en:
  fulfillment_business_status:
    business:
      awaiting_assembly: Awaiting assembly
      awaiting_dispatch: Awaiting dispatch
      in_delivery: In delivery
      delivered: Delivered
      cancelled: Cancelled
      needs_review: Needs review
    return:
      none: No return
      expected: Return expected
      at_platform_side: At platform
      returning_to_seller: Returning to seller
      received_by_seller: Received by seller
      no_physical_return: No goods returned
  reports:
    inventory:
      drawer:
        physical_stocktake:
          fbs_matrix:
            note: The business status shows how far the goods got in the delivery chain; the return status shows where returning goods are. Departed cells are deducted from the expected physical stock, cells received by the seller are added back, and not departed cells are still in the Belarus warehouse. Click a number to see the orders.
            row_header: Business status ╲ Return status
            kinds:
              not_left: Not departed
              left: Departed
              returned: Back in warehouse
              anomaly: Status anomaly
            legend: Legend
            anomaly_summary: Status anomalies (included above)
          fbs_orders_modal:
            title: FBS orders
            summary_cell: "%{business} × %{return}"
            quantity: Total quantity
            empty: No matching orders
            columns:
              platform_store: Platform / store
              order_number: Order number
              fulfillment_number: Fulfillment number
              ordered_at: Ordered at
              source_status: Platform status
              quantity: Quantity
            pagination_aria_label: FBS order list pagination
```

创建 `config/locales/fulfillment_business_status.ru.yml`：

```yaml
ru:
  fulfillment_business_status:
    business:
      awaiting_assembly: Ожидает сборки
      awaiting_dispatch: Ожидает отправки
      in_delivery: В доставке
      delivered: Доставлен
      cancelled: Отменён
      needs_review: Требует проверки
    return:
      none: Нет возврата
      expected: Ожидается возврат
      at_platform_side: На стороне площадки
      returning_to_seller: Возвращается продавцу
      received_by_seller: Получено продавцом
      no_physical_return: Без возврата товара
  reports:
    inventory:
      drawer:
        physical_stocktake:
          fbs_matrix:
            note: Бизнес-статус показывает, как далеко товар продвинулся по цепочке доставки, статус возврата — где находится возвращаемый товар. Ячейки «покинул склад» вычитаются из ожидаемого физического остатка, ячейки «получено продавцом» добавляются обратно, «не покинул склад» остаётся на складе в Беларуси. Нажмите на число, чтобы увидеть заказы.
            row_header: Бизнес-статус ╲ Статус возврата
            kinds:
              not_left: Не покинул склад
              left: Покинул склад
              returned: Вернулся на склад
              anomaly: Аномалия статуса
            legend: Легенда
            anomaly_summary: Аномалии статуса (включены выше)
          fbs_orders_modal:
            title: Заказы FBS
            summary_cell: "%{business} × %{return}"
            quantity: Итого
            empty: Подходящих заказов нет
            columns:
              platform_store: Площадка / магазин
              order_number: Номер заказа
              fulfillment_number: Номер отправления
              ordered_at: Дата заказа
              source_status: Статус площадки
              quantity: Количество
            pagination_aria_label: Страницы списка заказов FBS
```

- [ ] **Step 2: 写失败的测试**

在 `test/controllers/reports_controller_test.rb` 里，找到包含 `data-stocktake-section='fbs_orders'` 的测试（约 2680 行，"physical_stocktake" 页面测试），在现有断言之后追加（该测试里 `@sku` 已创建，且已有 `@sales_store`／`sku_product`；按该测试的上下文取 `sku_product`）：

```ruby
    assert_select ".inventory-physical-reconciliation__table.inventory-fbs-matrix", count: 1
```

并在文件末尾（类内）追加两个独立测试：

```ruby
  test "FBS matrix cells link to the order list modal" do
    store = @sales_store
    sku_product = Ec::SkuProduct.create!(
      sku_code: @sku.sku_code, store: store, product_id: "FBSM-#{@sku_code}", platform_sku_id: "7#{SecureRandom.random_number(10**8)}"
    )
    order = Ec::Order.create!(
      platform: "ozon", store: store, order_key: "FBSM-#{@sku_code}", external_order_id: "FBSM-#{@sku_code}",
      external_order_number: "FBSM-NUMBER-#{@sku_code}", order_status: "delivered", ordered_at: 2.days.ago
    )
    fulfillment = order.fulfillments.create!(
      platform: "ozon", store: store, external_fulfillment_id: "FBSM-F-#{@sku_code}",
      fulfillment_key: "FBSM-F-#{@sku_code}", fulfillment_type: "fbs", status: "delivered",
      source_status: "delivered", source_substatus: "posting_received",
      business_status: "delivered", return_business_status: "none"
    )
    Ec::OrderItem.create!(
      platform: "ozon", store: store, order: order, fulfillment: fulfillment, external_item_id: "FBSM-I-#{@sku_code}",
      platform_sku_id: sku_product.platform_sku_id, quantity: 3
    )

    get report_inventory_detail_path(@sku.sku_code),
      params: { detail_tab: "physical_stocktake" },
      headers: { "Accept" => "text/html", "Turbo-Frame" => "inventory_drawer_content" }

    assert_response :success
    assert_select "table.inventory-fbs-matrix a[data-turbo-frame='erp_modal'][href*='fbs_orders']", text: "3"

    get report_inventory_fbs_orders_path(
      @sku.sku_code, business_status: "delivered", return_business_status: "none"
    ), headers: { "Accept" => "text/html", "Turbo-Frame" => "erp_modal" }

    assert_response :success
    assert_select "turbo-frame#erp_modal"
    assert_select "td", text: "FBSM-NUMBER-#{@sku_code}"
  ensure
    Ec::OrderItem.where(order_id: order&.id).delete_all
    Ec::OrderFulfillment.where(order_id: order&.id).delete_all
    Ec::Order.where(id: order&.id).delete_all
    sku_product&.delete
  end

  test "FBS order list rejects statuses outside the vocabulary" do
    get report_inventory_fbs_orders_path(
      @sku.sku_code, business_status: "bogus", return_business_status: "none"
    ), headers: { "Accept" => "text/html", "Turbo-Frame" => "erp_modal" }

    assert_response :bad_request
  end
```

- [ ] **Step 3: 运行测试确认失败**

```bash
bin/rails test test/controllers/reports_controller_test.rb -n "/FBS matrix cells link|FBS order list rejects/"
```

Expected: ERROR，`undefined local variable or method 'report_inventory_fbs_orders_path'`。

- [ ] **Step 4: 路由与控制器**

`config/routes.rb` 在 `get "reports/inventory/:sku_code" => "reports#inventory_detail", as: :report_inventory_detail` 之后加：

```ruby
  get "reports/inventory/:sku_code/fbs_orders" => "reports#inventory_fbs_orders", as: :report_inventory_fbs_orders
```

`app/controllers/reports_controller.rb` 在 `inventory_detail` 动作之后加：

```ruby
  def inventory_fbs_orders
    @sku = Ec::Sku.find_by!(sku_code: params[:sku_code].to_s.upcase)
    business_status = params[:business_status].to_s.presence_in(Ec::FulfillmentBusinessStatus::BUSINESS_STATUSES)
    return_business_status = params[:return_business_status].to_s.presence_in(Ec::FulfillmentBusinessStatus::RETURN_STATUSES)
    return head :bad_request unless business_status && return_business_status

    @business_status = business_status
    @return_business_status = return_business_status
    @fbs_orders = Ec::InventoryFbsOrdersQuery.new(
      @sku,
      business_status: business_status,
      return_business_status: return_business_status,
      page: params[:jump_page].presence || params[:page]
    ).call
  end
```

`ReportsController` 默认会渲染 `app/views/reports/inventory_fbs_orders.html.erb`。

- [ ] **Step 5: 弹窗视图**

创建 `app/views/reports/inventory_fbs_orders.html.erb`（结构沿用 `erp/sku_batches/physical_stocktake_adjustments.html.erb`）：

```erb
<%= turbo_frame_tag "erp_modal" do %>
  <div class="erp-modal-backdrop" data-controller="modal" data-action="click->modal#closeOnBackdrop">
    <section class="erp-modal erp-modal--wide inventory-fbs-orders-modal"
             role="dialog"
             aria-modal="true"
             aria-labelledby="inventory-fbs-orders-modal-title">
      <div class="erp-modal__header">
        <div>
          <h2 id="inventory-fbs-orders-modal-title"><%= t("reports.inventory.drawer.physical_stocktake.fbs_orders_modal.title") %></h2>
          <p class="erp-modal__subtitle">
            <%= @sku.sku_code %> ·
            <%= t("reports.inventory.drawer.physical_stocktake.fbs_orders_modal.summary_cell",
                  business: t("fulfillment_business_status.business.#{@business_status}"),
                  return: t("fulfillment_business_status.return.#{@return_business_status}")) %>
          </p>
        </div>
        <button class="icon-button" type="button" aria-label="<%= t("common.actions.close") %>" data-action="modal#close">
          <i class="bi bi-x-lg" aria-hidden="true"></i>
        </button>
      </div>

      <% pagination = @fbs_orders[:pagination] %>
      <div class="inventory-fbs-orders-modal__summary">
        <span><%= t("reports.inventory.drawer.physical_stocktake.fbs_orders_modal.quantity") %></span>
        <strong><%= @fbs_orders[:rows].sum { |row| row[:quantity] } %><% if pagination[:total_pages] > 1 %> / <%= pagination[:total_count] %><% end %></strong>
      </div>

      <% if pagination[:total_pages] > 1 %>
        <%= render "reports/supply_orders/pagination",
                   report: { pagination: pagination },
                   page_param: :page,
                   turbo_frame: "erp_modal",
                   path_builder: ->(query) {
                     report_inventory_fbs_orders_path(
                       @sku.sku_code,
                       query.merge(business_status: @business_status, return_business_status: @return_business_status)
                     )
                   } %>
      <% end %>

      <%= table_viewport(class_name: "table-scroll--contained", max_height: "50vh") do %>
        <table class="inventory-detail-table">
          <thead>
            <tr>
              <th><%= t("reports.inventory.drawer.physical_stocktake.fbs_orders_modal.columns.platform_store") %></th>
              <th><%= t("reports.inventory.drawer.physical_stocktake.fbs_orders_modal.columns.order_number") %></th>
              <th><%= t("reports.inventory.drawer.physical_stocktake.fbs_orders_modal.columns.fulfillment_number") %></th>
              <th><%= t("reports.inventory.drawer.physical_stocktake.fbs_orders_modal.columns.ordered_at") %></th>
              <th><%= t("reports.inventory.drawer.physical_stocktake.fbs_orders_modal.columns.source_status") %></th>
              <th class="numeric"><%= t("reports.inventory.drawer.physical_stocktake.fbs_orders_modal.columns.quantity") %></th>
            </tr>
          </thead>
          <tbody>
            <% @fbs_orders[:rows].each do |row| %>
              <tr>
                <td><%= t("reports.inventory.drawer.sales_distribution.store_label", platform: row[:platform].to_s.upcase, store: row[:store_name]) %></td>
                <td><%= report_value(row[:order_number]) %></td>
                <td><%= report_value(row[:fulfillment_number]) %></td>
                <td><%= display_time(row[:ordered_at]) %></td>
                <td><%= row[:source_status_label].presence || t("reports.inventory.drawer.sales_distribution.no_status_evidence") %></td>
                <td class="numeric"><%= row[:quantity] %></td>
              </tr>
            <% end %>
            <% if @fbs_orders[:rows].empty? %>
              <tr><td colspan="6" class="empty-state"><%= t("reports.inventory.drawer.physical_stocktake.fbs_orders_modal.empty") %></td></tr>
            <% end %>
          </tbody>
        </table>
      <% end %>
    </section>
  </div>
<% end %>
```

- [ ] **Step 6: 交叉表视图**

在 `app/views/reports/_inventory_physical_reconciliation.html.erb` 里，把 `<% if active_section == "fbs_orders" %> ... <% end %>` 这一整块（约 69–109 行，包含 `data-stocktake-section="fbs_orders"` 的 div）替换为：

```erb
  <% if active_section == "fbs_orders" %>
  <% fbs_matrix = reconciliation[:fbs_matrix] || { cells: [], summary: {} } %>
  <% matrix_cells = fbs_matrix[:cells].index_by { |cell| [ cell[:business_status], cell[:return_business_status] ] } %>
  <% matrix_summary = fbs_matrix[:summary] %>
  <% return_statuses = Ec::FulfillmentBusinessStatus::RETURN_STATUSES %>
  <div class="inventory-physical-reconciliation__group" data-stocktake-section="fbs_orders">
    <div class="inventory-detail-panel__head">
      <h4><%= t("reports.inventory.drawer.physical_stocktake.sections.fbs_orders") %></h4>
      <p class="muted"><%= t("reports.inventory.drawer.physical_stocktake.fbs_matrix.note") %></p>
    </div>
    <div class="inventory-fbs-matrix__legend" aria-label="<%= t("reports.inventory.drawer.physical_stocktake.fbs_matrix.legend") %>">
      <% %w[not_left left returned].each do |kind| %>
        <span class="inventory-fbs-matrix__legend-item inventory-fbs-matrix__cell--<%= kind.dasherize %>">
          <%= t("reports.inventory.drawer.physical_stocktake.fbs_matrix.kinds.#{kind}") %>
        </span>
      <% end %>
      <span class="inventory-fbs-matrix__legend-item inventory-fbs-matrix__cell--anomaly">
        <%= t("reports.inventory.drawer.physical_stocktake.fbs_matrix.kinds.anomaly") %>
      </span>
    </div>
    <%= table_viewport(class_name: "table-scroll--horizontal") do %>
      <table class="inventory-distribution-table inventory-physical-reconciliation__table inventory-fbs-matrix">
        <thead><tr>
          <th><%= t("reports.inventory.drawer.physical_stocktake.fbs_matrix.row_header") %></th>
          <% return_statuses.each do |return_status| %>
            <th class="numeric"><%= t("fulfillment_business_status.return.#{return_status}") %></th>
          <% end %>
        </tr></thead>
        <tbody>
          <% Ec::FulfillmentBusinessStatus::BUSINESS_STATUSES.each do |business_status| %>
            <tr>
              <th scope="row"><%= t("fulfillment_business_status.business.#{business_status}") %></th>
              <% return_statuses.each do |return_status| %>
                <% cell = matrix_cells[[ business_status, return_status ]] %>
                <% if cell && cell[:quantity].positive? %>
                  <td class="numeric inventory-fbs-matrix__cell inventory-fbs-matrix__cell--<%= cell[:kind].dasherize %><%= " inventory-fbs-matrix__cell--anomaly" if cell[:anomaly] %>">
                    <%= link_to cell[:quantity],
                                report_inventory_fbs_orders_path(
                                  sku.sku_code,
                                  business_status: business_status,
                                  return_business_status: return_status,
                                  locale: params[:locale].presence
                                ),
                                data: { turbo_frame: "erp_modal" },
                                title: t("reports.inventory.drawer.physical_stocktake.fbs_matrix.kinds.#{cell[:kind]}") %>
                  </td>
                <% else %>
                  <td class="numeric muted">-</td>
                <% end %>
              <% end %>
            </tr>
          <% end %>
        </tbody>
        <tfoot>
          <tr class="inventory-distribution-table__summary">
            <td colspan="<%= return_statuses.size %>"><%= t("reports.inventory.drawer.labels.summary") %></td>
            <td class="numeric"><%= matrix_summary[:total_quantity].to_i %></td>
          </tr>
          <% if matrix_summary[:anomaly_quantity].to_i.positive? %>
            <tr>
              <td colspan="<%= return_statuses.size %>"><%= t("reports.inventory.drawer.physical_stocktake.fbs_matrix.anomaly_summary") %></td>
              <td class="numeric"><%= matrix_summary[:anomaly_quantity].to_i %></td>
            </tr>
          <% end %>
        </tfoot>
      </table>
    <% end %>
  </div>
  <% end %>
```

`colspan` 合计是 1（行表头）+ 6（退货状态列）= 7 列，汇总行的标签单元格占 6 列，数量单元格占最后 1 列，所以 `colspan` 用 `return_statuses.size`（= 6）。

- [ ] **Step 7: 样式**

在 `app/assets/stylesheets/application.css` 末尾加（只加这一段；该文件有用户未提交的改动，提交时用 `git add -p` 只暂存这一段）：

```css
.inventory-fbs-matrix th[scope="row"] { text-align: left; white-space: nowrap; }
.inventory-fbs-matrix__cell a { font-weight: 600; text-decoration: none; }
.inventory-fbs-matrix__cell--not-left { background: color-mix(in srgb, var(--success, #1a7f37) 12%, transparent); }
.inventory-fbs-matrix__cell--left { background: color-mix(in srgb, var(--warning, #b7791f) 12%, transparent); }
.inventory-fbs-matrix__cell--returned { background: color-mix(in srgb, var(--info, #2563eb) 12%, transparent); }
.inventory-fbs-matrix__cell--anomaly { outline: 2px dashed var(--danger, #c0392b); outline-offset: -2px; }
.inventory-fbs-matrix__legend { display: flex; flex-wrap: wrap; gap: 8px; margin: 8px 0; }
.inventory-fbs-matrix__legend-item { padding: 2px 8px; border-radius: 4px; font-size: 12px; }
.inventory-fbs-orders-modal__summary { display: flex; gap: 8px; align-items: baseline; margin: 8px 0; }
```

- [ ] **Step 8: 运行测试确认通过**

```bash
bin/rails test test/controllers/reports_controller_test.rb -n "/physical stocktake|physical_stocktake|FBS matrix cells link|FBS order list rejects/"
```

Expected: 通过。该文件既有的 FBS 板块断言 `.inventory-physical-reconciliation__table tfoot .inventory-distribution-table__summary` + `td:first-child` 文本 `汇总` 仍成立（本方案保留了该类名和文案）。若某条旧断言引用了 27 阶段的文案（如 `平台已接收并分拣`），按新交叉表改成对应的新状态文案。

- [ ] **Step 9: 提交**

```bash
git add config/locales/fulfillment_business_status.zh.yml config/locales/fulfillment_business_status.en.yml \
  config/locales/fulfillment_business_status.ru.yml \
  app/controllers/reports_controller.rb app/views/reports/_inventory_physical_reconciliation.html.erb \
  app/views/reports/inventory_fbs_orders.html.erb test/controllers/reports_controller_test.rb
git add -p config/routes.rb app/assets/stylesheets/application.css   # 只暂存本任务新增的 hunk
git commit -m "feat: show FBS business status matrix with order drill-down

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 10: 对比基线并核对差异

**Files:**
- Create: `docs/superpowers/baselines/2026-10-13-physical-stocktake-after.md`（核对结果记录）

**Interfaces:**
- Consumes: Task 6 已在开发库回填的新字段，Task 8 的新查询，基线文件（Task 1）

- [ ] **Step 1: 捕获重构后的数字**

```bash
export PATH="$HOME/.rvm/rubies/ruby-3.4.8/bin:$PATH" GEM_HOME="$HOME/.rvm/gems/ruby-3.4.8" GEM_PATH="$HOME/.rvm/gems/ruby-3.4.8:$HOME/.rvm/gems/ruby-3.4.8@global"
bin/rails runner script/backfill_fulfillment_business_status.rb --dry-run | head -3   # 确认 changed=0，库里的值是最新的
mkdir -p tmp
bin/rails runner script/physical_stocktake_baseline.rb capture tmp/physical_stocktake_after.json
```

Expected: `changed=0`；`wrote tmp/physical_stocktake_after.json (236 skus)`。

- [ ] **Step 2: 对比**

```bash
bin/rails runner script/physical_stocktake_baseline.rb compare \
  docs/superpowers/baselines/2026-10-13-physical-stocktake-baseline.json \
  tmp/physical_stocktake_after.json
```

Expected：不应出现订单／退货条数不一致的警告；最后一行 `20 of 236 skus differ`。

- [ ] **Step 3: 逐个核对差异**

对照基线文档里的"预期差异"表，把输出的 20 个 SKU 逐个对上：

| 预期 | SKU |
|---|---|
| WB `waiting + complete` 改为已离仓（合计 −20） | JJ005-4、ZJ092、SLHL002-2、QJD001-3、MPJ001-YL、LDD005、KJ-228-WT、KJ-208-SV、CYQ95-BK |
| 卡住的 `waiting/new` 订单不再重复加回（合计 −29） | CYQ97-WT、JXZ-GREY-01、JZJJ-001、CYQ97-BK、CZY001、LDD001-BK、KJ-228-SV、KJ-207-GY、JZDJ-YS、JXZ-WHITE-02 |
| 多发货单 Ozon 订单（+1） | KJ-226-GY |

三类之外出现的任何 SKU、或数量与上表不符的，都是缺陷：先用下面的命令定位，修复后回到 Step 1。

```bash
bin/rails runner '
sku = Ec::Sku.find_by!(sku_code: "<SKU>")
matrix = Ec::InventoryFbsStatusMatrixQuery.new(sku).call
matrix[:cells].each { |c| puts [c[:business_status], c[:return_business_status], c[:quantity], c[:kind], c[:anomaly]].join(" | ") }
'
```

与基线 JSON 里该 SKU 的 `fbs_order_rows` 并排比较（`python3 -I -c` 读 JSON 并按 `status_key` 汇总）。

- [ ] **Step 4: 记录核对结果并提交**

创建 `docs/superpowers/baselines/2026-10-13-physical-stocktake-after.md`，写入：

- 对比命令与输出的最后一行；
- 差异 SKU 表（SKU、变化、原因，与上面三类对应）；
- 重构后全库合计（与基线文档的合计表同格式）；
- 任何计划之外的差异及其处理结论（若无写"无"）。

```bash
git add docs/superpowers/baselines/2026-10-13-physical-stocktake-after.md
git commit -m "docs: record physical stocktake comparison after business status refactor

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 5: 运行本次涉及的全部测试文件**

```bash
bin/rails test \
  test/services/ec/fulfillment_business_status_test.rb \
  test/services/ec/fulfillment_business_status/updater_test.rb \
  test/services/ec/fulfillment_business_status/backfill_test.rb \
  test/models/ec/business_status_validation_test.rb \
  test/services/ec/inventory_fbs_status_matrix_query_test.rb \
  test/services/ec/inventory_fbs_orders_query_test.rb \
  test/services/ec/inventory_physical_reconciliation_query_test.rb \
  test/services/ec/inventory_page_row_query_test.rb \
  test/services/ec/order_import_test.rb \
  test/services/ec/returns/sync_test.rb \
  test/controllers/reports_controller_test.rb
```

Expected: 本次新增和修改的测试全部通过。`reports_controller_test.rb`、`order_import_test.rb` 里与本次无关的既有失败（见 Global Constraints）不算；判断方法：对失败用例 `git stash` 后重跑，确认在改动前就失败。

---

## 执行后的收尾提醒

- 上线顺序：先部署代码与迁移 → 在线上用 `script/backfill_fulfillment_business_status.rb --dry-run` 看差异数 → 去掉 `--dry-run` 回填（`kamal app exec` 会在 web 和 job 两个容器上各跑一次，写操作加 `--roles web`）→ 再核对线上盘库数字。
- 落库值可能因漏掉触发路径而过期（尤其是 WB 统计销售行晚于订单同步到达）：定期跑一次 `--dry-run`，`changed` 不为 0 就说明有路径漏了。
- 后续迁移（不在本计划范围）：账面库存台账读新字段、其余读 `order_status` 的报表、FBO／FBW 物理盘库。
