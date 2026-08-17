# Inventory Book Stock Adjustment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Update the inventory service and debug script so book-stock uses purchase plus adjustment batches, counts all WB sales, and ignores supply quantities in stock formulas.

**Architecture:** Put the new source-of-truth logic in `Ec::SkuInventoryOverview`, validate it with a dedicated service test, then align the debug script and reference document to the same formula. Leave controllers and current UI untouched so the future inventory page can consume the corrected service output later.

**Tech Stack:** Rails 8, ActiveRecord, Minitest, Rails runner script, Markdown docs

---

### Task 1: Add Failing Service Coverage For The New Inventory Formula

**Files:**
- Create: `test/services/ec/sku_inventory_overview_test.rb`
- Test: `test/services/ec/sku_inventory_overview_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
require "test_helper"

class Ec::SkuInventoryOverviewTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(4).upcase
    @sku = Ec::Sku.create!(sku_code: "INV-SVC-#{@token}", product_name: "库存服务测试")

    @wb_account = RawWb::SellerAccount.create!(
      name: "wb-svc-#{@token}",
      api_token: "token-#{@token}",
      company_type: "small"
    )
    @ozon_account = RawOzon::SellerAccount.create!(
      company_name: "ozon-svc-#{@token}",
      client_id: "client-#{@token}",
      api_key: "key-#{@token}",
      company_type: "small"
    )

    @wb_store = Ec::Store.create!(
      platform: "wb",
      store_name: "WB 库存服务店 #{@token}",
      company_type: "small",
      wb_raw_account_id: @wb_account.id,
      is_active: true
    )
    @ozon_store = Ec::Store.create!(
      platform: "ozon",
      store_name: "Ozon 库存服务店 #{@token}",
      company_type: "small",
      ozon_raw_account_id: @ozon_account.id,
      is_active: true
    )

    Ec::SkuProduct.create!(
      sku_code: @sku.sku_code,
      store: @wb_store,
      product_id: "123456",
      platform_sku_id: "WB-CHRT-#{@token}"
    )
    Ec::SkuProduct.create!(
      sku_code: @sku.sku_code,
      store: @ozon_store,
      product_id: "OZON-PROD-#{@token}",
      platform_sku_id: "3902460130",
      offer_id: "OFFER-#{@token}"
    )

    Ec::SkuBatch.create!(
      sku_code: @sku.sku_code,
      batch_code: "NORMAL-#{@token}",
      status: "received",
      batch_type: :normal,
      purchased_quantity: 30,
      received_quantity: 30,
      purchase_unit_price_cny: 1
    )
    Ec::SkuBatch.create!(
      sku_code: @sku.sku_code,
      batch_code: "ADJUST-#{@token}",
      status: "closed",
      batch_type: :wb_fbw_offset,
      purchased_quantity: 0,
      received_quantity: -4,
      defect_offset_note: "WB FBW correction",
      purchase_unit_price_cny: 1
    )

    wb_fbw_order = Ec::Order.create!(
      platform: "wb",
      store: @wb_store,
      external_order_id: "WB-FBW-#{@token}",
      external_order_number: "WB-FBW-#{@token}",
      order_key: "wb:#{@wb_store.id}:WB-FBW-#{@token}",
      order_status: "delivered",
      ordered_at: Time.zone.parse("2026-06-10 10:00:00"),
      synced_at: Time.zone.parse("2026-06-10 10:05:00")
    )
    wb_fbw_fulfillment = wb_fbw_order.fulfillments.create!(
      platform: "wb",
      store: @wb_store,
      external_fulfillment_id: "WB-FBW-F-#{@token}",
      fulfillment_key: "wb:#{@wb_store.id}:WB-FBW-F-#{@token}",
      fulfillment_type: "fbw",
      status: "delivered"
    )
    wb_fbw_order.items.create!(
      fulfillment: wb_fbw_fulfillment,
      platform: "wb",
      store: @wb_store,
      external_item_id: "WB-FBW-I-#{@token}",
      platform_sku_id: "123456",
      offer_id: "WB-OFFER-#{@token}",
      product_name_source: "WB FBW 商品",
      quantity: 5,
      unit_price: 50,
      payout: 200,
      commission_amount: 20,
      discount_amount: 0,
      currency_code: "BYN"
    )

    wb_fbs_order = Ec::Order.create!(
      platform: "wb",
      store: @wb_store,
      external_order_id: "WB-FBS-#{@token}",
      external_order_number: "WB-FBS-#{@token}",
      order_key: "wb:#{@wb_store.id}:WB-FBS-#{@token}",
      order_status: "delivered",
      ordered_at: Time.zone.parse("2026-06-11 10:00:00"),
      synced_at: Time.zone.parse("2026-06-11 10:05:00")
    )
    wb_fbs_fulfillment = wb_fbs_order.fulfillments.create!(
      platform: "wb",
      store: @wb_store,
      external_fulfillment_id: "WB-FBS-F-#{@token}",
      fulfillment_key: "wb:#{@wb_store.id}:WB-FBS-F-#{@token}",
      fulfillment_type: "fbs",
      status: "delivered"
    )
    wb_fbs_order.items.create!(
      fulfillment: wb_fbs_fulfillment,
      platform: "wb",
      store: @wb_store,
      external_item_id: "WB-FBS-I-#{@token}",
      platform_sku_id: "123456",
      offer_id: "WB-OFFER-#{@token}",
      product_name_source: "WB FBS 商品",
      quantity: 7,
      unit_price: 50,
      payout: 280,
      commission_amount: 20,
      discount_amount: 0,
      currency_code: "BYN"
    )

    ozon_order = Ec::Order.create!(
      platform: "ozon",
      store: @ozon_store,
      external_order_id: "OZON-#{@token}",
      external_order_number: "OZON-#{@token}",
      order_key: "ozon:#{@ozon_store.id}:OZON-#{@token}",
      order_status: "delivered",
      ordered_at: Time.zone.parse("2026-06-12 10:00:00"),
      synced_at: Time.zone.parse("2026-06-12 10:05:00")
    )
    ozon_order.items.create!(
      platform: "ozon",
      store: @ozon_store,
      external_item_id: "OZON-I-#{@token}",
      platform_sku_id: "3902460130",
      offer_id: "OFFER-#{@token}",
      product_name_source: "Ozon 商品",
      quantity: 9,
      unit_price: 100,
      payout: 900,
      commission_amount: 20,
      discount_amount: 0,
      currency_code: "BYN"
    )

    RawWb::GoodsReturn.create!(
      account: @wb_account,
      shk_id: 20_000_000 + @token.to_i(16),
      nm_id: 123_456,
      barcode: "WB-RETURN-#{@token}",
      status: "ready_to_return",
      synced_at: Time.zone.parse("2026-06-13 10:00:00")
    )
    RawOzon::Return.create!(
      account: @ozon_account,
      return_id: 30_000_000 + @token.to_i(16),
      return_schema: "FBO",
      return_type: "Return",
      posting_number: "OZON-#{@token}",
      order_number: "OZON-#{@token}",
      ozon_sku: 3_902_460_130,
      offer_id: "OFFER-#{@token}",
      product_name: "Ozon 商品",
      quantity: 2,
      raw_json: {},
      synced_at: Time.zone.parse("2026-06-14 10:00:00")
    )

    RawWb::SupplyItem.create!(
      account: @wb_account,
      wb_supply_id: "WB-SUPPLY-#{@token}",
      nm_id: 123_456,
      accepted_qty: 100,
      synced_at: Time.zone.parse("2026-06-15 10:00:00")
    )
    RawOzon::SupplyOrder.create!(
      account: @ozon_account,
      supply_order_id: "OZON-SUPPLY-#{@token}",
      status: "COMPLETED",
      items: { "3902460130" => 100 },
      raw_json: {},
      synced_at: Time.zone.parse("2026-06-15 10:00:00")
    )

    Ec::SkuInventoryLevel.create!(
      sku_code: @sku.sku_code,
      platform: "wb",
      account_id: @wb_account.id,
      store: @wb_store,
      store_name: @wb_store.store_name,
      fulfillment_type: "fbw",
      quantity: 4,
      is_latest: true,
      synced_at: Time.zone.parse("2026-06-16 10:00:00"),
      metadata: {}
    )
    Ec::SkuInventoryLevel.create!(
      sku_code: @sku.sku_code,
      platform: "ozon",
      account_id: @ozon_account.id,
      store: @ozon_store,
      store_name: @ozon_store.store_name,
      fulfillment_type: "fbo",
      quantity: 6,
      is_latest: true,
      synced_at: Time.zone.parse("2026-06-16 10:05:00"),
      metadata: {}
    )
  end

  teardown do
    Ec::SkuInventoryLevel.where(sku_code: @sku.sku_code).delete_all
    RawOzon::SupplyOrder.where(account_id: @ozon_account.id).delete_all
    RawWb::SupplyItem.where(account_id: @wb_account.id).delete_all
    RawOzon::Return.where(account_id: @ozon_account.id).delete_all
    RawWb::GoodsReturn.where(account_id: @wb_account.id).delete_all
    Ec::OrderItem.joins(:order).where(ec_orders: { store_id: [@wb_store.id, @ozon_store.id] }).delete_all
    Ec::OrderFulfillment.where(store_id: [@wb_store.id, @ozon_store.id]).delete_all
    Ec::Order.where(store_id: [@wb_store.id, @ozon_store.id]).delete_all
    Ec::SkuBatch.where(sku_code: @sku.sku_code).delete_all
    Ec::SkuProduct.where(sku_code: @sku.sku_code).delete_all
    Ec::Store.where(id: [@wb_store.id, @ozon_store.id]).delete_all
    RawWb::SellerAccount.where(id: @wb_account.id).delete_all
    RawOzon::SellerAccount.where(id: @ozon_account.id).delete_all
    Ec::Sku.with_deleted.where(id: @sku.id).delete_all
  end

  test "summarizes purchase adjustment sales returns and ignores supply quantities in stock formulas" do
    overview = Ec::SkuInventoryOverview.new(@sku).call
    summary = overview[:summary]

    assert_equal 30, summary[:purchase_quantity]
    assert_equal(-4, summary[:adjustment_quantity])
    assert_equal 26, summary[:received_quantity]
    assert_equal 21, summary[:sales_quantity]
    assert_equal 3, summary[:return_quantity]
    assert_equal 200, summary[:supply_quantity]
    assert_equal 10, summary[:platform_stock]
    assert_equal 8, summary[:book_stock]
    assert_equal(-2, summary[:available_stock])

    wb_row = overview[:store_rows].find { |row| row[:platform] == "wb" }
    ozon_row = overview[:store_rows].find { |row| row[:platform] == "ozon" }

    assert_equal 12, wb_row[:sales_quantity]
    assert_equal 1, wb_row[:return_quantity]
    assert_equal 100, wb_row[:supply_quantity]

    assert_equal 9, ozon_row[:sales_quantity]
    assert_equal 2, ozon_row[:return_quantity]
    assert_equal 100, ozon_row[:supply_quantity]
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `SKIP_JS_BUILD=1 bundle exec ruby bin/rails test test/services/ec/sku_inventory_overview_test.rb`
Expected: FAIL because `Ec::SkuInventoryOverview` does not yet expose `purchase_quantity` / `adjustment_quantity` and still subtracts `supply_quantity` from `book_stock`.

- [ ] **Step 3: Keep the failure focused on the service contract**

```ruby
    assert_equal 30, summary[:purchase_quantity]
    assert_equal(-4, summary[:adjustment_quantity])
    assert_equal 8, summary[:book_stock]
```

Do not add controller assertions here. This task is intentionally service-only.

- [ ] **Step 4: Re-run the same test file to verify the red state is still the missing feature**

Run: `SKIP_JS_BUILD=1 bundle exec ruby bin/rails test test/services/ec/sku_inventory_overview_test.rb`
Expected: FAIL on the new summary contract or formula values, not because of unrelated setup problems.

- [ ] **Step 5: Commit**

```bash
git add test/services/ec/sku_inventory_overview_test.rb
git commit -m "test: cover inventory book stock adjustments"
```

### Task 2: Implement The Service-Level Inventory Logic

**Files:**
- Modify: `app/services/ec/sku_inventory_overview.rb`
- Test: `test/services/ec/sku_inventory_overview_test.rb`

- [ ] **Step 1: Add a batch summary helper**

```ruby
    def batch_summary
      @batch_summary ||= begin
        rows = @sku.batches
          .where(status: %w[received closed])
          .group(:batch_type)
          .sum(:received_quantity)

        purchase_quantity = rows.fetch("normal", 0).to_i
        adjustment_quantity = rows.except("normal").values.sum(&:to_i)

        {
          purchase_quantity: purchase_quantity,
          adjustment_quantity: adjustment_quantity,
          received_quantity: purchase_quantity + adjustment_quantity
        }
      end
    end
```

- [ ] **Step 2: Update `summary` to use the new batch totals and ignore supply quantities in formulas**

```ruby
    def summary(store_rows, latest_levels)
      sold = store_rows.sum { |row| row[:sales_quantity] }
      returned = store_rows.sum { |row| row[:return_quantity] }
      supply = store_rows.sum { |row| row[:supply_quantity] }
      platform_stock = latest_levels.sum(&:quantity)
      batches = batch_summary
      received = batches[:received_quantity]

      {
        purchase_quantity: batches[:purchase_quantity],
        adjustment_quantity: batches[:adjustment_quantity],
        received_quantity: received,
        sales_quantity: sold,
        return_quantity: returned,
        supply_quantity: supply,
        platform_stock: platform_stock,
        book_stock: received - sold + returned,
        available_stock: received - sold + returned - platform_stock
      }
    end
```

- [ ] **Step 3: Leave store-row supply values informational only**

```ruby
        {
          platform: platform,
          store_id: store_id,
          store_name: store_name,
          account_id: account_id,
          sales_quantity: orders[:sales_quantity].to_i,
          return_quantity: return_rows[key].to_i,
          supply_quantity: supply_quantity_for(platform, key),
          platform_stock: levels.sum(&:quantity),
          latest_synced_at: levels.map(&:synced_at).compact.max
        }
```

Do not remove `supply_quantity` from store rows in this task. Only stop using it in stock formulas.

- [ ] **Step 4: Keep WB order attribution fulfillment-agnostic**

```ruby
        Ec::OrderItem
          .joins(:order, :store)
          .joins(order_item_sku_product_join_sql)
          .where(ec_sku_products: { sku_code: @sku.sku_code })
          .where.not(ec_orders: { order_status: "cancelled" })
```

Do not add any `fulfillment_type = 'fbs'` filter for WB.

- [ ] **Step 5: Run the targeted service test to verify it passes**

Run: `SKIP_JS_BUILD=1 bundle exec ruby bin/rails test test/services/ec/sku_inventory_overview_test.rb`
Expected: PASS with `purchase_quantity`, `adjustment_quantity`, `book_stock`, and `available_stock` matching the new formula.

- [ ] **Step 6: Commit**

```bash
git add app/services/ec/sku_inventory_overview.rb test/services/ec/sku_inventory_overview_test.rb
git commit -m "feat: update inventory overview stock formula"
```

### Task 3: Align The Inventory Debug Script And Reference Document

**Files:**
- Modify: `script/20260618_check_inventory.rb`
- Modify: `docs/库存计算260615.md`
- Test: `test/services/ec/sku_inventory_overview_test.rb`

- [ ] **Step 1: Update batch totals in the script**

```ruby
  purchase_quantity = Ec::SkuBatch
    .where(sku_code: sku_code, status: %w[received closed], batch_type: :normal)
    .sum(:received_quantity)

  adjustment_quantity = Ec::SkuBatch
    .where(sku_code: sku_code, status: %w[received closed])
    .where.not(batch_type: Ec::SkuBatch.batch_types[:normal])
    .sum(:received_quantity)

  received_quantity = purchase_quantity + adjustment_quantity
```

- [ ] **Step 2: Change WB sales in the script to count all WB orders and remove WB supply from the formula**

```ruby
  wb_sales = wb_nm_ids.empty? ? 0 :
    not_cancelled.(
      Ec::OrderItem.where(platform: "wb", platform_sku_id: wb_nm_ids)
    ).sum(:quantity)

  wb_net = wb_sales - wb_goods_return
  net_sales = wb_net + ozon_sold - ozon_returns
  book_stock = received_quantity - net_sales
```

Delete the `wb_supply` query and remove it from both the output and the formula commentary.

- [ ] **Step 3: Update the script output labels**

```ruby
  row "采购数量（normal）",         bs[:purchase_quantity]
  row "补正调整数量（non-normal）", bs[:adjustment_quantity]
  row "总入库（received/closed）",  bs[:received_quantity]
  row "WB 部分（销售 − 退货）",     bs[:wb_net]
  row "  └ WB 销售",               bs[:wb_sales]
```

- [ ] **Step 4: Update the document formulas and examples to match**

```markdown
账面库存 =
  总入库
  − (WB净销售 + Ozon净销售)

其中：
  总入库 = 采购数量 + 补正调整数量
  采购数量 = SUM(received_quantity WHERE batch_type = normal)
  补正调整数量 = SUM(received_quantity WHERE batch_type != normal)
  WB净销售 = WB销售 − WB退货
```

Also remove any statement that WB FBW supply participates in inventory quantity formulas, and explicitly state that supply quantities do not participate in inventory calculations for any platform.

- [ ] **Step 5: Run the service test again as a regression guard**

Run: `SKIP_JS_BUILD=1 bundle exec ruby bin/rails test test/services/ec/sku_inventory_overview_test.rb`
Expected: PASS, confirming the script/doc alignment did not require further service changes.

- [ ] **Step 6: Inspect the final diff**

Run: `git diff -- app/services/ec/sku_inventory_overview.rb script/20260618_check_inventory.rb docs/库存计算260615.md test/services/ec/sku_inventory_overview_test.rb`
Expected: only the service, script, doc, and new service test are changed for this task.

- [ ] **Step 7: Commit**

```bash
git add app/services/ec/sku_inventory_overview.rb script/20260618_check_inventory.rb docs/库存计算260615.md test/services/ec/sku_inventory_overview_test.rb
git commit -m "docs: align inventory formula with batch adjustments"
```
