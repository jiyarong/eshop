# Book Inventory Ledger Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the three divergent book-stock calculations with one `Ec::Inventory::BookLedger` that answers "how much do I own and how much of it can I sell (own side + platform side)", without depending on where goods physically are.

**Architecture:** A pure-Ruby service computes per-SKU received/gross-sales/reversal/bucket numbers from batches, order items (matched to SKUs by the existing hard link), returns and a few raw-table dispatch signals. `compose` adds the platform side from inventory-level snapshots. The three existing consumers (`SkuInventoryOverview`, `SkuInventoryOverviewBatchQuery`, `InventoryTurnoverMetricsQuery`) delegate to it after a shadow-diff release.

**Tech Stack:** Rails 8, PostgreSQL, Minitest (`use_transactional_tests = false`, tests clean up their own data), Ruby 3.4.8 via rvm.

**Spec:** `docs/superpowers/specs/2026-10-12-book-inventory-ledger-design.md`

## Global Constraints

- Stale open orders: status `pending`/`processing` and `ordered_at` older than **45 days** do not count as sales (spec 4.6).
- Order-to-SKU attribution is the hard link `ec_sku_products` (store, platform, `platform_sku_id` for Ozon / `product_id` for WB). Never use `ec_order_items.sku_code` or `offer_id` for statistics.
- Unsellable is classified automatically from return status/reason (spec 4.5).
- Persisted daily snapshots (`ec_snapshots`) are **not** backfilled; only an effective-date note is shown on the trend.
- Page GET requests must stay read-only: no sync, no writes, no snapshot capture.
- All user-visible text goes through I18n (zh, en, ru).
- Do not run frontend builds. Do not start the web server.
- `test/test_helper.rb` has `use_transactional_tests = false`: every test creates unique data (random token) and deletes it in `teardown`.
- Run Ruby with: `export PATH="$HOME/.rvm/rubies/ruby-3.4.8/bin:$PATH" GEM_HOME="$HOME/.rvm/gems/ruby-3.4.8" GEM_PATH="$HOME/.rvm/gems/ruby-3.4.8:$HOME/.rvm/gems/ruby-3.4.8@global"`.
- The working tree has unrelated uncommitted edits (pricing workbench files, locale files, `.idea/`, `docs/` scratch files, an untracked draft migration). Only `git add` the paths a task lists. For the locale files (`config/locales/{zh,en,ru}.yml`) that also contain unrelated hunks, stage only your hunks: save `git diff -- <file>` to a temp file, delete the unrelated hunks, then `git apply --cached <patch>`.
- `return_items.restockable` stays in the database and in the returns UI, but no longer influences `ledger_total`.
- Release split: **Release 1** = Tasks 1-7b (no behavior change: adds the ledger, the diff report, the WB backfill and the completeness check). **Release 2** = Tasks 8-14 (cut over).

---

## File Structure

| File | Responsibility |
|---|---|
| `app/services/ec/inventory/book_ledger/return_rules.rb` (new) | Pure status/reason tables: return location, reversal, unsellable |
| `app/services/ec/inventory/book_ledger.rb` (new) | Per-SKU ledger numbers, `compose`, `unattributed` |
| `app/services/ec/inventory/ledger_diff.rb` (new, removed in Task 11) | Legacy vs ledger comparison used for the shadow release |
| `lib/tasks/ec_inventory_ledger.rake` (new, removed in Task 11) | `ec:inventory:ledger_diff` CSV report |
| `app/services/ec/order_import/wb.rb` (modify) | `import_unlinked_stats_only_orders` backfill |
| `lib/tasks/ec_wb_orders.rake` (new) | `ec:wb_orders:import_unlinked_stats` |
| `app/services/ec/inventory/order_completeness.rb`, `lib/tasks/ec_inventory_completeness.rake` (new) | Counts raw orders/postings that never became orders |
| `app/services/ec/sku_inventory_overview_batch_query.rb` (modify) | Delegate to ledger |
| `app/services/ec/inventory_turnover_metrics_query.rb` (modify) | Delegate to ledger |
| `app/services/ec/sku_inventory_overview.rb` (modify) | Summary and store rows from ledger |
| `app/models/ec/return_item.rb` (modify) | Remove `restockable_for_book_inventory` |
| `app/views/reports/_sku_inventory_trend.html.erb`, locales (modify) | Effective-date note, label rename |
| `test/support/book_ledger_fixtures.rb` (new) | Shared fixture helpers |

---

### Task 1: Return rules (pure tables)

**Files:**
- Create: `app/services/ec/inventory/book_ledger.rb` (empty class stub; Task 2 replaces its content. Zeitwerk needs the parent file to exist, otherwise `BookLedger` is autovivified as a Module and `class BookLedger` in `return_rules.rb` raises a TypeError)
- Create: `app/services/ec/inventory/book_ledger/return_rules.rb`
- Test: `test/services/ec/inventory/book_ledger/return_rules_test.rb`

**Interfaces:**
- Produces: `Ec::Inventory::BookLedger::ReturnRules.location(platform, source_status)` → `:own | :platform | :transit | nil` (`nil` = not a reversal); `Ec::Inventory::BookLedger::ReturnRules.unsellable?(platform, reason:, return_type:)` → Boolean.

- [ ] **Step 1: Write the failing test**

```ruby
require "test_helper"

class Ec::Inventory::BookLedger::ReturnRulesTest < ActiveSupport::TestCase
  Rules = Ec::Inventory::BookLedger::ReturnRules

  test "maps Ozon return statuses to a location or no reversal" do
    assert_equal :transit, Rules.location("ozon", "MovingToOzon")
    assert_equal :platform, Rules.location("ozon", "ReturnedToOzon")
    assert_equal :transit, Rules.location("ozon", "MovingToSeller")
    assert_equal :transit, Rules.location("ozon", "ReadyForSeller")
    assert_equal :own, Rules.location("ozon", "ReceivedBySeller")
    %w[OnSellerApproval WaitingShipment Approved MoneyReturned PartialCompensationReturned
       Cancelled CancelledDisputeNotOpen Rejected].each do |status|
      assert_nil Rules.location("ozon", status), status
    end
    assert_nil Rules.location("ozon", nil)
  end

  test "maps WB goods-return statuses: issued is own side, everything else is on its way" do
    assert_equal :own, Rules.location("wb", "Выдано")
    assert_equal :transit, Rules.location("wb", "В пути в пвз")
    assert_equal :transit, Rules.location("wb", "Готов к выдаче")
    assert_nil Rules.location("wb", nil)
  end

  test "classifies unsellable returns by Ozon reason and WB return type" do
    assert Rules.unsellable?("ozon", reason: "Товар не работает / брак", return_type: nil)
    assert Rules.unsellable?("ozon", reason: "Упаковка и товар повреждены", return_type: nil)
    assert Rules.unsellable?("ozon", reason: "Товар поддельный", return_type: nil)
    assert_not Rules.unsellable?("ozon", reason: "Покупатель передумал", return_type: nil)
    assert Rules.unsellable?("wb", reason: nil, return_type: "Возврат брака")
    assert_not Rules.unsellable?("wb", reason: nil, return_type: "Возврат неверного вложения")
    assert_not Rules.unsellable?("wb", reason: nil, return_type: nil)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/services/ec/inventory/book_ledger/return_rules_test.rb`
Expected: FAIL / ERROR with `uninitialized constant Ec::Inventory`.

- [ ] **Step 3: Write minimal implementation**

First the parent stub `app/services/ec/inventory/book_ledger.rb`:

```ruby
module Ec
  module Inventory
    class BookLedger
    end
  end
end
```

Then `app/services/ec/inventory/book_ledger/return_rules.rb`:

```ruby
module Ec
  module Inventory
    class BookLedger
      # Status and reason tables of the book ledger (spec sections 4.3-4.5). Pure functions, no database access.
      module ReturnRules
        OZON_LOCATIONS = {
          "MovingToOzon" => :transit,
          "ReturnedToOzon" => :platform,
          "MovingToSeller" => :transit,
          "ReadyForSeller" => :transit,
          "ReceivedBySeller" => :own
        }.freeze

        WB_RECEIVED_STATUS = "Выдано".freeze

        OZON_UNSELLABLE_REASONS = [
          "Товар не работает / брак",
          "Товар поврежден, но упаковка цела",
          "Упаковка и товар повреждены",
          "Товар поддельный",
          "Товар сломался при эксплуатации",
          "Товар в неполной комплектации"
        ].freeze

        WB_UNSELLABLE_RETURN_TYPES = [ "Возврат брака" ].freeze

        # Where the returned goods are, or nil when the status does not reverse the sale.
        def self.location(platform, source_status)
          return nil if source_status.blank?

          case platform.to_s
          when "ozon" then OZON_LOCATIONS[source_status.to_s]
          when "wb" then source_status.to_s == WB_RECEIVED_STATUS ? :own : :transit
          end
        end

        def self.unsellable?(platform, reason:, return_type:)
          case platform.to_s
          when "ozon" then OZON_UNSELLABLE_REASONS.include?(reason.to_s)
          when "wb" then WB_UNSELLABLE_RETURN_TYPES.include?(return_type.to_s)
          else false
          end
        end
      end
    end
  end
end
```

Note: `BookLedger` is a plain class (no superclass) in both files; Task 2 replaces the stub's content.

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/services/ec/inventory/book_ledger/return_rules_test.rb`
Expected: 3 runs, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add app/services/ec/inventory/book_ledger.rb app/services/ec/inventory/book_ledger/return_rules.rb test/services/ec/inventory/book_ledger/return_rules_test.rb
git commit -m "Add book ledger return status and unsellable rules"
```

---

### Task 2: Shared fixtures and ledger skeleton (batches, compose)

**Files:**
- Create: `test/support/book_ledger_fixtures.rb`
- Modify (replace the Task 1 stub content): `app/services/ec/inventory/book_ledger.rb`
- Test: `test/services/ec/inventory/book_ledger_test.rb`

**Interfaces:**
- Produces: `Ec::Inventory::BookLedger.call(sku_codes:, as_of: nil)` → `{ "SKU" => entry }`, where `entry` has keys `:purchase_quantity, :adjustment_quantity, :received_quantity, :gross_sales_quantity, :reversed_quantity, :ledger_total, :return_in_transit_quantity, :return_at_platform_quantity, :unsellable_quantity, :stale_open_order_quantity, :by_store`. `as_of: nil` means "now, no cutoff"; a Time means "orders ordered on or before it, batches received on or before its date".
- Produces: `Ec::Inventory::BookLedger.compose(entry, platform_sellable:, platform_inbound:)` → entry merged with `:platform_sellable, :platform_inbound, :platform_side, :own_side, :sellable`.
- Produces test helpers: `setup_ledger_world`, `teardown_ledger_world`, `ledger_batch`, `ledger_order`, `ledger_return`.

- [ ] **Step 1: Write the shared fixtures**

```ruby
require "securerandom"

# Shared data builders for book ledger tests. Include it in a test class and call
# setup_ledger_world in setup / teardown_ledger_world in teardown.
module BookLedgerFixtures
  def setup_ledger_world
    @token = SecureRandom.hex(4).upcase
    @sku = Ec::Sku.create!(sku_code: "LEDGER-#{@token}", product_name: "Ledger #{@token}")
    @wb_account = RawWb::SellerAccount.create!(
      name: "wb-ledger-#{@token}", api_token: "token-#{@token}", company_type: "small"
    )
    @ozon_account = RawOzon::SellerAccount.create!(
      company_name: "ozon-ledger-#{@token}", client_id: "client-#{@token}",
      api_key: "key-#{@token}", company_type: "small"
    )
    @wb_store = Ec::Store.create!(
      platform: "wb", store_name: "WB Ledger #{@token}", company_type: "small",
      wb_raw_account_id: @wb_account.id, is_active: true
    )
    @ozon_store = Ec::Store.create!(
      platform: "ozon", store_name: "Ozon Ledger #{@token}", company_type: "small",
      ozon_raw_account_id: @ozon_account.id, is_active: true
    )
    @wb_product = Ec::SkuProduct.create!(
      sku_code: @sku.sku_code, store: @wb_store, product_id: "NM-#{@token}",
      platform_sku_id: "WBCHRT-#{@token}"
    )
    @ozon_product = Ec::SkuProduct.create!(
      sku_code: @sku.sku_code, store: @ozon_store, product_id: "OZP-#{@token}",
      platform_sku_id: "9#{@token.to_i(16) % 100_000_000}", offer_id: "OFFER-#{@token}"
    )
  end

  def teardown_ledger_world
    store_ids = [ @wb_store&.id, @ozon_store&.id ].compact
    return_ids = Ec::Return.where(store_id: store_ids).select(:id)
    Ec::ReturnSourceLink.where(return_id: return_ids).delete_all
    Ec::ReturnItem.where(return_id: return_ids).delete_all
    Ec::Return.where(store_id: store_ids).delete_all
    Ec::OrderSourceLink.where(order_id: Ec::Order.where(store_id: store_ids).select(:id)).delete_all
    Ec::OrderItem.where(store_id: store_ids).delete_all
    Ec::OrderFulfillment.where(store_id: store_ids).delete_all
    Ec::Order.where(store_id: store_ids).delete_all
    RawWb::Order.where(account_id: @wb_account&.id).delete_all
    RawOzon::PostingFbs.where(account_id: @ozon_account&.id).delete_all
    Ec::SkuInventoryLevel.where(sku_code: @sku&.sku_code).delete_all
    Ec::SkuBatch.where(sku_code: @sku&.sku_code).delete_all
    Ec::SkuProduct.where(sku_code: @sku&.sku_code).delete_all
    Ec::Store.where(id: store_ids).delete_all
    RawWb::SellerAccount.where(id: @wb_account&.id).delete_all
    RawOzon::SellerAccount.where(id: @ozon_account&.id).delete_all
    Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
  end

  def ledger_batch(quantity, type: :normal, status: "received", received_on: nil)
    attributes = {
      sku_code: @sku.sku_code, batch_code: "B-#{SecureRandom.hex(4)}", status: status, batch_type: type,
      purchased_quantity: quantity, received_quantity: quantity, purchase_unit_price_cny: 1,
      received_on: received_on
    }
    attributes[:defect_offset_note] = "ledger test" unless type.to_s == "normal"
    Ec::SkuBatch.create!(attributes)
  end

  # Creates an order with one fulfillment and one item attributed to @sku.
  def ledger_order(platform:, status:, quantity: 1, fulfillment_type: "fbs", fulfillment_status: nil,
                   ordered_at: Time.current - 5.days, source_status: nil, source_substatus: nil,
                   with_fulfillment: true, platform_sku_id: nil)
    store = platform == "wb" ? @wb_store : @ozon_store
    product_id = platform == "wb" ? @wb_product.product_id : @ozon_product.platform_sku_id
    key = "#{platform}-#{SecureRandom.hex(6)}"
    order = Ec::Order.create!(
      platform: platform, store: store, order_key: key, external_order_id: key,
      order_status: status, ordered_at: ordered_at
    )
    fulfillment = nil
    if with_fulfillment
      fulfillment = order.fulfillments.create!(
        platform: platform, store: store, external_fulfillment_id: key,
        fulfillment_key: "#{platform}:#{store.id}:#{key}", fulfillment_type: fulfillment_type,
        status: fulfillment_status || status, source_status: source_status, source_substatus: source_substatus
      )
    end
    order.items.create!(
      fulfillment: fulfillment, platform: platform, store: store, external_item_id: key,
      platform_sku_id: platform_sku_id || product_id, quantity: quantity
    )
    order
  end

  def ledger_return(order, source_status:, quantity: 1, reason: nil, payload: {})
    product = order.platform == "wb" ? @wb_product : @ozon_product
    key = "RET-#{SecureRandom.hex(6)}"
    record = Ec::Return.create!(
      platform: order.platform, store: order.store, order: order, return_key: key, external_return_id: key,
      return_type: "customer_return", source_status: source_status, source_substatus: reason,
      source_payload: payload
    )
    record.items.create!(
      platform: order.platform, store: order.store, sku_product: product, item_key: key,
      quantity: quantity, restockable: false
    )
    record
  end

  def ledger_entry(as_of: nil)
    Ec::Inventory::BookLedger.call(sku_codes: [ @sku.sku_code ], as_of: as_of).fetch(@sku.sku_code.upcase)
  end
end
```

- [ ] **Step 2: Write the failing tests**

```ruby
require "test_helper"
require_relative "../../../support/book_ledger_fixtures"

class Ec::Inventory::BookLedgerTest < ActiveSupport::TestCase
  include BookLedgerFixtures

  setup { setup_ledger_world }
  teardown { teardown_ledger_world }

  test "splits received batches into purchase and adjustment and ignores stocktake and unreceived batches" do
    ledger_batch(30)
    ledger_batch(-4, type: :wb_fbw_offset)
    ledger_batch(-5, type: :physical_stocktake_adjustment)
    ledger_batch(10, status: "ordered")

    entry = ledger_entry

    assert_equal 30, entry[:purchase_quantity]
    assert_equal(-4, entry[:adjustment_quantity])
    assert_equal 26, entry[:received_quantity]
    assert_equal 26, entry[:ledger_total]
  end

  test "only counts batches received on or before as_of" do
    ledger_batch(10, received_on: Date.new(2026, 9, 1))
    ledger_batch(7, received_on: Date.new(2026, 9, 20))

    entry = ledger_entry(as_of: Time.zone.parse("2026-09-15 23:59:59"))

    assert_equal 10, entry[:received_quantity]
  end

  test "composes platform side, own side and sellable from a ledger entry" do
    entry = {
      ledger_total: 20, return_in_transit_quantity: 3, return_at_platform_quantity: 2, unsellable_quantity: 1
    }

    composed = Ec::Inventory::BookLedger.compose(entry, platform_sellable: 6, platform_inbound: 2)

    assert_equal 8, composed[:platform_side]
    assert_equal 12, composed[:own_side]
    assert_equal 12, composed[:sellable]
    assert_equal 6, composed[:platform_sellable]
    assert_equal 2, composed[:platform_inbound]
  end
end
```

- [ ] **Step 3: Run test to verify it fails**

Run: `bin/rails test test/services/ec/inventory/book_ledger_test.rb`
Expected: ERROR `undefined method 'call' for class Ec::Inventory::BookLedger`.

- [ ] **Step 4: Write minimal implementation**

```ruby
module Ec
  module Inventory
    # Single source of truth for book stock: how many units the seller owns and how much of it is sellable.
    # Does not look at where goods physically are (that is Ec::InventoryPhysicalReconciliationQuery).
    class BookLedger
      STALE_OPEN_ORDER_DAYS = 45
      OPEN_STATUSES = %w[pending processing].freeze
      WB_DISPATCHED_SUPPLIER_STATUS = "complete".freeze
      RECEIVED_BATCH_STATUSES = %w[received closed].freeze
      STATUS_BUCKETS = {
        "pending" => "pending", "processing" => "processing", "shipped" => "shipping", "delivered" => "signed"
      }.freeze

      def self.call(sku_codes:, as_of: nil)
        new(sku_codes: sku_codes, as_of: as_of).call
      end

      def self.compose(entry, platform_sellable:, platform_inbound:)
        platform_side = platform_sellable.to_i + platform_inbound.to_i
        own_side = entry[:ledger_total] - platform_side
        entry.merge(
          platform_sellable: platform_sellable.to_i,
          platform_inbound: platform_inbound.to_i,
          platform_side: platform_side,
          own_side: own_side,
          sellable: platform_sellable.to_i + own_side - entry[:return_in_transit_quantity].to_i -
            entry[:return_at_platform_quantity].to_i - entry[:unsellable_quantity].to_i
        )
      end

      def initialize(sku_codes:, as_of:)
        @sku_codes = Array(sku_codes).map { |code| code.to_s.upcase }.uniq
        @as_of = as_of
      end

      def call
        return {} if @sku_codes.empty?

        ledger = @sku_codes.index_with { empty_entry }
        apply_batches(ledger)
        ledger.each_value do |entry|
          entry[:ledger_total] = entry[:received_quantity] - entry[:gross_sales_quantity] + entry[:reversed_quantity]
        end
        ledger
      end

      private

      def empty_entry
        {
          purchase_quantity: 0, adjustment_quantity: 0, received_quantity: 0,
          gross_sales_quantity: 0, reversed_quantity: 0, ledger_total: 0,
          return_in_transit_quantity: 0, return_at_platform_quantity: 0, unsellable_quantity: 0,
          stale_open_order_quantity: 0, by_store: {}
        }
      end

      def apply_batches(ledger)
        scope = Ec::SkuBatch
          .where(sku_code: @sku_codes, status: RECEIVED_BATCH_STATUSES)
          .where.not(batch_type: :physical_stocktake_adjustment)
        if @as_of
          scope = scope.where(
            "ec_sku_batches.received_on <= :date OR (ec_sku_batches.received_on IS NULL AND ec_sku_batches.created_at <= :cutoff)",
            date: @as_of.to_date, cutoff: @as_of
          )
        end

        scope.group(:sku_code, :batch_type).sum(:received_quantity).each do |(sku_code, batch_type), quantity|
          entry = ledger[sku_code.to_s.upcase]
          next unless entry

          if batch_type.to_s == "normal"
            entry[:purchase_quantity] += quantity.to_i
          else
            entry[:adjustment_quantity] += quantity.to_i
          end
          entry[:received_quantity] += quantity.to_i
        end
      end
    end
  end
end
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bin/rails test test/services/ec/inventory/book_ledger_test.rb test/services/ec/inventory/book_ledger/return_rules_test.rb`
Expected: 6 runs, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add test/support/book_ledger_fixtures.rb app/services/ec/inventory/book_ledger.rb test/services/ec/inventory/book_ledger_test.rb
git commit -m "Add book ledger skeleton with batches and compose"
```

---

### Task 3: Gross sales, cancellation, WB returned, stale orders, per-store counts

**Files:**
- Modify: `app/services/ec/inventory/book_ledger.rb`
- Test: `test/services/ec/inventory/book_ledger_test.rb`

**Interfaces:**
- Consumes: Task 2 `BookLedger`, `BookLedgerFixtures`.
- Produces: `entry[:gross_sales_quantity]`, `entry[:stale_open_order_quantity]`, `entry[:by_store][[platform, store_id]] = { gross_sales_quantity:, reversed_quantity:, status_counts: { "pending"/"processing"/"shipping"/"signed" => Integer } }`. Private `order_rows` returns an Array of Hashes with keys `:sku_code, :order_id, :platform, :store_id, :quantity, :order_status, :ordered_at, :fulfillment_status, :fulfillment_source_status, :fulfillment_source_substatus, :external_fulfillment_id`.

- [ ] **Step 1: Write the failing tests** (append inside `Ec::Inventory::BookLedgerTest`)

```ruby
  test "counts every fulfillment type and excludes cancelled, WB returned and stale open orders" do
    ledger_batch(100)
    ledger_order(platform: "wb", status: "delivered", quantity: 7)
    ledger_order(platform: "wb", status: "delivered", quantity: 5, fulfillment_type: "fbw")
    ledger_order(platform: "ozon", status: "delivered", quantity: 9)
    ledger_order(platform: "ozon", status: "shipped", quantity: 2, fulfillment_type: "fbo")
    ledger_order(platform: "wb", status: "cancelled", quantity: 4)
    ledger_order(platform: "wb", status: "returned", quantity: 3)
    ledger_order(platform: "ozon", status: "returned", quantity: 6)
    ledger_order(platform: "wb", status: "processing", quantity: 8, ordered_at: Time.current - 60.days)
    ledger_order(platform: "wb", status: "processing", quantity: 1, ordered_at: Time.current - 5.days)

    entry = ledger_entry

    assert_equal 30, entry[:gross_sales_quantity]
    assert_equal 8, entry[:stale_open_order_quantity]
    assert_equal 70, entry[:ledger_total]

    wb = entry[:by_store][[ "wb", @wb_store.id ]]
    ozon = entry[:by_store][[ "ozon", @ozon_store.id ]]
    assert_equal 13, wb[:gross_sales_quantity]
    assert_equal 12, wb[:status_counts]["signed"]
    assert_equal 1, wb[:status_counts]["processing"]
    assert_equal 17, ozon[:gross_sales_quantity]
    assert_equal 9, ozon[:status_counts]["signed"]
    assert_equal 2, ozon[:status_counts]["shipping"]
  end

  test "uses the fulfillment status over the order level status" do
    ledger_batch(100)
    ledger_order(platform: "ozon", status: "cancelled", fulfillment_status: "delivered", quantity: 3)
    ledger_order(platform: "ozon", status: "delivered", fulfillment_status: "cancelled", quantity: 2)

    entry = ledger_entry

    assert_equal 3, entry[:gross_sales_quantity]
    assert_equal 97, entry[:ledger_total]
  end

  test "falls back to the order status when an item has no fulfillment" do
    ledger_batch(100)
    ledger_order(platform: "wb", status: "returned", quantity: 2, with_fulfillment: false)
    ledger_order(platform: "wb", status: "delivered", quantity: 4, with_fulfillment: false)

    assert_equal 4, ledger_entry[:gross_sales_quantity]
  end

  test "only counts orders placed on or before as_of" do
    ledger_batch(100)
    ledger_order(platform: "wb", status: "delivered", quantity: 3, ordered_at: Time.zone.parse("2026-09-01 10:00:00"))
    ledger_order(platform: "wb", status: "delivered", quantity: 5, ordered_at: Time.zone.parse("2026-09-20 10:00:00"))

    entry = ledger_entry(as_of: Time.zone.parse("2026-09-15 23:59:59"))

    assert_equal 3, entry[:gross_sales_quantity]
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/services/ec/inventory/book_ledger_test.rb`
Expected: 4 new tests FAIL (`gross_sales_quantity` is 0).

- [ ] **Step 3: Implement** — in `book_ledger.rb` change `call` and add the private methods

Replace `call` with:

```ruby
      def call
        return {} if @sku_codes.empty?

        ledger = @sku_codes.index_with { empty_entry }
        apply_batches(ledger)
        apply_orders(ledger)
        ledger.each_value do |entry|
          entry[:ledger_total] = entry[:received_quantity] - entry[:gross_sales_quantity] + entry[:reversed_quantity]
        end
        ledger
      end
```

Add below `apply_batches`:

```ruby
      ORDER_COLUMNS = %w[
        ec_sku_products.sku_code ec_order_items.order_id ec_order_items.platform ec_order_items.store_id
        ec_order_items.quantity ec_orders.order_status ec_orders.ordered_at ledger_f.status
        ledger_f.source_status ledger_f.source_substatus ledger_f.external_fulfillment_id
      ].freeze
      ORDER_KEYS = %i[
        sku_code order_id platform store_id quantity order_status ordered_at fulfillment_status
        fulfillment_source_status fulfillment_source_substatus external_fulfillment_id
      ].freeze

      def order_rows
        scope = Ec::OrderItem
          .joins(:order)
          .joins(Ec::InventoryOrderSalesDistributionQuery::ORDER_ITEM_JOIN)
          .joins("LEFT JOIN ec_order_fulfillments ledger_f ON ledger_f.id = ec_order_items.fulfillment_id")
          .where(ec_sku_products: { sku_code: @sku_codes })
        scope = scope.where("ec_orders.ordered_at <= ?", @as_of) if @as_of

        scope.pluck(*ORDER_COLUMNS.map { |column| Arel.sql(column) }).map do |values|
          row = ORDER_KEYS.zip(values).to_h
          row[:sku_code] = row[:sku_code].to_s.upcase
          row
        end
      end

      def apply_orders(ledger)
        stale_before = (@as_of || Time.current) - STALE_OPEN_ORDER_DAYS.days

        order_rows.group_by { |row| [ row[:order_id], row[:sku_code] ] }.each_value do |items|
          entry = ledger[items.first[:sku_code]]
          next unless entry

          items.each do |item|
            quantity = item[:quantity].to_i
            status = item[:fulfillment_status].presence || item[:order_status]

            if unsold_status?(item[:platform], status)
              next
            elsif OPEN_STATUSES.include?(status) && item[:ordered_at] && item[:ordered_at] < stale_before
              entry[:stale_open_order_quantity] += quantity
            else
              entry[:gross_sales_quantity] += quantity
              store_entry = store_entry(entry, item)
              store_entry[:gross_sales_quantity] += quantity
              bucket = STATUS_BUCKETS[status]
              store_entry[:status_counts][bucket] += quantity if bucket
            end
          end
        end
      end

      # Cancelled orders, and WB orders the platform marks as returned, are not sales.
      def unsold_status?(platform, status)
        status == "cancelled" || (platform == "wb" && status == "returned")
      end

      def store_entry(entry, item)
        entry[:by_store][[ item[:platform], item[:store_id] ]] ||= {
          gross_sales_quantity: 0, reversed_quantity: 0,
          status_counts: STATUS_BUCKETS.values.index_with { 0 }
        }
      end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/services/ec/inventory/book_ledger_test.rb`
Expected: 7 runs, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add app/services/ec/inventory/book_ledger.rb test/services/ec/inventory/book_ledger_test.rb
git commit -m "Compute gross sales, stale open orders and per-store counts in the book ledger"
```

---

### Task 4: Return reversal and location buckets

**Files:**
- Modify: `app/services/ec/inventory/book_ledger.rb`
- Test: `test/services/ec/inventory/book_ledger_test.rb`

**Interfaces:**
- Consumes: Task 3 `order_rows`, `store_entry`, `unsold_status?`; Task 1 `ReturnRules`.
- Produces: `entry[:reversed_quantity]`, `entry[:return_in_transit_quantity]`, `entry[:return_at_platform_quantity]`, `entry[:unsellable_quantity]` and `entry[:by_store][...][:reversed_quantity]`.

- [ ] **Step 1: Write the failing tests** (append inside the test class)

```ruby
  test "reverses sold items by the status of linked returns and buckets where the goods are" do
    ledger_batch(100)
    received = ledger_order(platform: "ozon", status: "delivered", quantity: 3)
    ledger_return(received, source_status: "ReceivedBySeller", quantity: 2)
    at_platform = ledger_order(platform: "ozon", status: "delivered")
    ledger_return(at_platform, source_status: "ReturnedToOzon")
    moving = ledger_order(platform: "ozon", status: "delivered")
    ledger_return(moving, source_status: "MovingToSeller")
    refunded = ledger_order(platform: "ozon", status: "delivered")
    ledger_return(refunded, source_status: "MoneyReturned")
    rejected = ledger_order(platform: "ozon", status: "delivered")
    ledger_return(rejected, source_status: "Rejected")

    entry = ledger_entry

    assert_equal 7, entry[:gross_sales_quantity]
    assert_equal 4, entry[:reversed_quantity]
    assert_equal 97, entry[:ledger_total]
    assert_equal 1, entry[:return_at_platform_quantity]
    assert_equal 1, entry[:return_in_transit_quantity]
    assert_equal 0, entry[:unsellable_quantity]
    assert_equal 4, entry[:by_store][[ "ozon", @ozon_store.id ]][:reversed_quantity]
  end

  test "never reverses more than the sold quantity" do
    ledger_batch(100)
    order = ledger_order(platform: "ozon", status: "delivered", quantity: 1)
    ledger_return(order, source_status: "ReceivedBySeller", quantity: 5)

    entry = ledger_entry

    assert_equal 1, entry[:reversed_quantity]
    assert_equal 100, entry[:ledger_total]
  end

  test "classifies reversed goods as unsellable by Ozon reason and WB return type" do
    ledger_batch(100)
    ozon = ledger_order(platform: "ozon", status: "delivered")
    ledger_return(ozon, source_status: "ReceivedBySeller", reason: "Товар не работает / брак")
    wb = ledger_order(platform: "wb", status: "delivered")
    ledger_return(wb, source_status: "Выдано", payload: { "return_type" => "Возврат брака" })
    sellable = ledger_order(platform: "ozon", status: "delivered")
    ledger_return(sellable, source_status: "ReceivedBySeller", reason: "Покупатель передумал")

    entry = ledger_entry

    assert_equal 3, entry[:reversed_quantity]
    assert_equal 2, entry[:unsellable_quantity]
    assert_equal 100, entry[:ledger_total]
  end

  test "buckets goods of cancelled orders that already left the warehouse" do
    ledger_batch(100)
    # WB handed over for delivery (supplier status complete), no return yet -> on its way back.
    ledger_order(platform: "wb", status: "cancelled", quantity: 2, source_substatus: "complete")
    # WB cancelled before dispatch -> never left, no bucket.
    ledger_order(platform: "wb", status: "cancelled", quantity: 1, source_substatus: "cancel")
    # Fulfillment substatus reads cancelled but the raw WB order is complete.
    stale_substatus = ledger_order(platform: "wb", status: "cancelled", quantity: 1, source_substatus: "cancelled")
    raw_order = RawWb::Order.create!(
      account: @wb_account, wb_order_id: 70_000_000_000 + @token.to_i(16), nm_id: 1,
      delivery_type: "fbs", wb_status: "canceled_by_client", supplier_status: "complete"
    )
    Ec::OrderSourceLink.create!(
      order: stale_substatus, platform: "wb", source_type: "RawWb::Order", source_id: raw_order.id,
      source_role: "primary", source_key: raw_order.wb_order_id.to_s
    )
    # Ozon with a delivery transfer time -> on its way back; without -> never left.
    handed_over = ledger_order(platform: "ozon", status: "cancelled")
    RawOzon::PostingFbs.create!(
      account: @ozon_account, posting_number: handed_over.items.first.external_item_id, status: "cancelled",
      delivering_date: Time.current - 3.days, raw_json: {}, created_at: Time.current
    )
    ledger_order(platform: "ozon", status: "cancelled")
    # WB defect cancelled after dispatch, no return yet -> unsellable.
    ledger_order(platform: "wb", status: "cancelled", source_status: "defect", source_substatus: "complete")
    # WB cancelled after dispatch and already issued back -> own side, no bucket.
    back = ledger_order(platform: "wb", status: "cancelled", source_substatus: "complete")
    ledger_return(back, source_status: "Выдано")

    entry = ledger_entry

    assert_equal 4, entry[:return_in_transit_quantity]
    assert_equal 1, entry[:unsellable_quantity]
    assert_equal 0, entry[:return_at_platform_quantity]
    assert_equal 0, entry[:gross_sales_quantity]
    assert_equal 0, entry[:reversed_quantity]
    assert_equal 100, entry[:ledger_total]
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/services/ec/inventory/book_ledger_test.rb`
Expected: 4 new tests FAIL (reversed/bucket quantities are 0).

- [ ] **Step 3: Implement** — replace `apply_orders` and add helpers in `book_ledger.rb`

```ruby
      def apply_orders(ledger)
        rows = order_rows
        return if rows.empty?

        returns_by_order = Ec::Return.where(order_id: rows.map { |row| row[:order_id] }.uniq)
          .includes(items: :sku_product).group_by(&:order_id)
        wb_dispatched = wb_dispatched_order_ids(rows.select { |row| row[:platform] == "wb" }.map { |row| row[:order_id] }.uniq)
        ozon_dispatched = ozon_dispatched_postings(
          rows.select { |row| row[:platform] == "ozon" }.filter_map { |row| row[:external_fulfillment_id] }.uniq
        )
        stale_before = (@as_of || Time.current) - STALE_OPEN_ORDER_DAYS.days

        rows.group_by { |row| [ row[:order_id], row[:sku_code] ] }.each do |(order_id, sku_code), items|
          entry = ledger[sku_code]
          next unless entry

          returns = counting_returns(returns_by_order.fetch(order_id, []), sku_code)
          sold_quantity = 0
          unsold = []

          items.each do |item|
            quantity = item[:quantity].to_i
            status = item[:fulfillment_status].presence || item[:order_status]

            if unsold_status?(item[:platform], status)
              unsold << item
            elsif OPEN_STATUSES.include?(status) && item[:ordered_at] && item[:ordered_at] < stale_before
              entry[:stale_open_order_quantity] += quantity
            else
              sold_quantity += quantity
              store_entry = store_entry(entry, item)
              store_entry[:gross_sales_quantity] += quantity
              bucket = STATUS_BUCKETS[status]
              store_entry[:status_counts][bucket] += quantity if bucket
            end
          end

          entry[:gross_sales_quantity] += sold_quantity
          apply_sold_reversal(entry, items.first, returns, sold_quantity)
          apply_unsold_goods(entry, unsold, returns, wb_dispatched, ozon_dispatched)
        end
      end

      # Sold items whose sale a return reverses: goods are owned again whatever their location.
      def apply_sold_reversal(entry, item, returns, sold_quantity)
        return if sold_quantity <= 0

        parts, = take_from_returns(returns, sold_quantity)
        reversed = parts.sum { |part| part[:quantity] }
        return if reversed.zero?

        entry[:reversed_quantity] += reversed
        store_entry(entry, item)[:reversed_quantity] += reversed
        parts.each { |part| add_location_bucket(entry, part) }
      end

      # Cancelled / WB-returned items: nothing to reverse, but goods that already left are on their way back.
      def apply_unsold_goods(entry, unsold, returns, wb_dispatched, ozon_dispatched)
        return if unsold.empty?

        quantity = unsold.sum { |item| item[:quantity].to_i }
        parts, remainder = take_from_returns(returns, quantity)
        parts.each { |part| add_location_bucket(entry, part) }
        return unless remainder.positive?
        return unless unsold.any? { |item| dispatched?(item, wb_dispatched, ozon_dispatched) }

        if unsold.any? { |item| item[:fulfillment_source_status] == "defect" }
          entry[:unsellable_quantity] += remainder
        else
          entry[:return_in_transit_quantity] += remainder
        end
      end

      def dispatched?(item, wb_dispatched, ozon_dispatched)
        case item[:platform]
        when "wb"
          item[:fulfillment_source_substatus] == WB_DISPATCHED_SUPPLIER_STATUS || wb_dispatched.include?(item[:order_id])
        when "ozon"
          ozon_dispatched.include?(item[:external_fulfillment_id])
        else
          false
        end
      end

      # Returns of this SKU on the order that count as goods coming back, as mutable hashes.
      def counting_returns(return_records, sku_code)
        return_records.filter_map do |record|
          location = ReturnRules.location(record.platform, record.source_status)
          next unless location

          quantity = record.items
            .select { |item| item.sku_product&.sku_code.to_s.upcase == sku_code }
            .sum { |item| item.quantity.to_i }
          next unless quantity.positive?

          {
            location: location,
            quantity: quantity,
            unsellable: ReturnRules.unsellable?(
              record.platform, reason: record.source_substatus, return_type: record.source_payload.to_h["return_type"]
            )
          }
        end
      end

      # Takes up to `quantity` units from the returns in order; returns [parts, unallocated_remainder].
      def take_from_returns(returns, quantity)
        parts = []
        needed = quantity
        returns.each do |record|
          break unless needed.positive?

          take = [ record[:quantity], needed ].min
          next unless take.positive?

          parts << record.merge(quantity: take)
          record[:quantity] -= take
          needed -= take
        end
        [ parts, needed ]
      end

      def add_location_bucket(entry, part)
        if part[:unsellable]
          entry[:unsellable_quantity] += part[:quantity]
        elsif part[:location] == :platform
          entry[:return_at_platform_quantity] += part[:quantity]
        elsif part[:location] == :transit
          entry[:return_in_transit_quantity] += part[:quantity]
        end
      end

      def wb_dispatched_order_ids(order_ids)
        return Set.new if order_ids.empty?

        links = Ec::OrderSourceLink
          .where(order_id: order_ids, source_type: "RawWb::Order", source_role: "primary")
          .pluck(:order_id, :source_id)
        complete_ids = RawWb::Order
          .where(id: links.map(&:last), supplier_status: WB_DISPATCHED_SUPPLIER_STATUS)
          .pluck(:id).to_set
        links.filter_map { |order_id, raw_id| order_id if complete_ids.include?(raw_id) }.to_set
      end

      def ozon_dispatched_postings(posting_numbers)
        return Set.new if posting_numbers.empty?

        RawOzon::PostingFbs.where(posting_number: posting_numbers).where.not(delivering_date: nil)
          .pluck(:posting_number).to_set
      end
```

Note: in the test above `handed_over.items.first.external_item_id` equals the fulfillment's `external_fulfillment_id` because `ledger_order` uses the same `key` for both.

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/services/ec/inventory/book_ledger_test.rb test/services/ec/inventory/book_ledger/return_rules_test.rb`
Expected: 11 runs, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add app/services/ec/inventory/book_ledger.rb test/services/ec/inventory/book_ledger_test.rb
git commit -m "Reverse sales by returns and bucket in-transit, platform and unsellable goods"
```

---

### Task 5: Unattributed sales

**Files:**
- Modify: `app/services/ec/inventory/book_ledger.rb`
- Test: `test/services/ec/inventory/book_ledger_test.rb`

**Interfaces:**
- Produces: `Ec::Inventory::BookLedger.unattributed(as_of: nil)` → `[{ platform:, platform_sku_id:, quantity: }]` sorted by quantity descending; only non-cancelled order items that match no `ec_sku_products` row.

- [ ] **Step 1: Write the failing test**

```ruby
  test "lists non-cancelled sales that match no SKU product" do
    unknown_id = "UNKNOWN-#{@token}"
    ledger_order(platform: "ozon", status: "delivered", quantity: 4, platform_sku_id: unknown_id)
    ledger_order(platform: "ozon", status: "cancelled", quantity: 9, platform_sku_id: unknown_id)
    ledger_order(platform: "ozon", status: "delivered", quantity: 2)

    rows = Ec::Inventory::BookLedger.unattributed.select { |row| row[:platform_sku_id] == unknown_id }

    assert_equal [ { platform: "ozon", platform_sku_id: unknown_id, quantity: 4 } ], rows
    assert_equal 0, Ec::Inventory::BookLedger.unattributed.count { |row| row[:platform_sku_id] == @ozon_product.platform_sku_id }
  end
```

- [ ] **Step 2: Run to verify it fails**

Run: `bin/rails test test/services/ec/inventory/book_ledger_test.rb -n /unattributed|match no SKU/`
Expected: ERROR `undefined method 'unattributed'`.

- [ ] **Step 3: Implement** — add as a class method after `self.compose`

```ruby
      UNATTRIBUTED_SQL = <<~SQL.squish.freeze
        NOT EXISTS (
          SELECT 1 FROM ec_sku_products p
          WHERE p.store_id = ec_order_items.store_id AND p.platform = ec_order_items.platform
            AND (
              (ec_order_items.platform = 'ozon' AND p.platform_sku_id = ec_order_items.platform_sku_id)
              OR (ec_order_items.platform = 'wb' AND p.product_id = ec_order_items.platform_sku_id)
            )
        )
      SQL

      def self.unattributed(as_of: nil)
        scope = Ec::OrderItem.joins(:order)
          .where.not(ec_orders: { order_status: "cancelled" })
          .where(UNATTRIBUTED_SQL)
        scope = scope.where("ec_orders.ordered_at <= ?", as_of) if as_of

        scope.group("ec_order_items.platform", "ec_order_items.platform_sku_id").sum(:quantity)
          .map { |(platform, platform_sku_id), quantity| { platform: platform, platform_sku_id: platform_sku_id, quantity: quantity.to_i } }
          .sort_by { |row| -row[:quantity] }
      end
```

- [ ] **Step 4: Run to verify it passes**

Run: `bin/rails test test/services/ec/inventory/book_ledger_test.rb`
Expected: 12 runs, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add app/services/ec/inventory/book_ledger.rb test/services/ec/inventory/book_ledger_test.rb
git commit -m "List unattributed sales in the book ledger"
```

---

### Task 6: Shadow diff report (legacy vs ledger)

**Files:**
- Create: `app/services/ec/inventory/ledger_diff.rb`
- Create: `lib/tasks/ec_inventory_ledger.rake`
- Test: `test/services/ec/inventory/ledger_diff_test.rb`

**Interfaces:**
- Consumes: `BookLedger.call`, scopes `OrderItem.deductible_from_book_inventory`, `ReturnItem.restockable_for_book_inventory` (still present until Task 11).
- Produces: `Ec::Inventory::LedgerDiff.call(sku_codes:)` → `[{ sku_code:, legacy:, ledger:, diff:, stale_open:, in_transit:, at_platform:, unsellable: }]`.

- [ ] **Step 1: Write the failing test**

```ruby
require "test_helper"
require_relative "../../../support/book_ledger_fixtures"

class Ec::Inventory::LedgerDiffTest < ActiveSupport::TestCase
  include BookLedgerFixtures

  setup { setup_ledger_world }
  teardown { teardown_ledger_world }

  test "reports legacy and ledger book stock side by side" do
    ledger_batch(100)
    ledger_order(platform: "wb", status: "delivered", quantity: 10)
    # Stale processing order: legacy deducts it, the ledger does not.
    ledger_order(platform: "wb", status: "processing", quantity: 4, ordered_at: Time.current - 100.days)

    row = Ec::Inventory::LedgerDiff.call(sku_codes: [ @sku.sku_code ]).sole

    assert_equal @sku.sku_code, row[:sku_code]
    assert_equal 86, row[:legacy]
    assert_equal 90, row[:ledger]
    assert_equal 4, row[:diff]
    assert_equal 4, row[:stale_open]
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `bin/rails test test/services/ec/inventory/ledger_diff_test.rb`
Expected: ERROR `uninitialized constant Ec::Inventory::LedgerDiff`.

- [ ] **Step 3: Implement**

```ruby
module Ec
  module Inventory
    # Release-1 helper: compares the legacy book stock formula with the ledger for the shadow period.
    # Removed together with the legacy scopes once the ledger is the only implementation.
    class LedgerDiff
      def self.call(sku_codes:)
        codes = Array(sku_codes).map { |code| code.to_s.upcase }.uniq
        ledger = Ec::Inventory::BookLedger.call(sku_codes: codes)
        join = Ec::InventoryOrderSalesDistributionQuery::ORDER_ITEM_JOIN
        sold = Ec::OrderItem.deductible_from_book_inventory.joins(join)
          .where(ec_sku_products: { sku_code: codes })
          .group("ec_sku_products.sku_code").sum(:quantity)
        returned = Ec::ReturnItem.restockable_for_book_inventory.joins(:sku_product)
          .where(ec_sku_products: { sku_code: codes })
          .group("ec_sku_products.sku_code").sum(:quantity)

        codes.map do |code|
          entry = ledger.fetch(code)
          legacy = entry[:received_quantity] - sold.fetch(code, 0).to_i + returned.fetch(code, 0).to_i
          {
            sku_code: code,
            legacy: legacy,
            ledger: entry[:ledger_total],
            diff: entry[:ledger_total] - legacy,
            stale_open: entry[:stale_open_order_quantity],
            in_transit: entry[:return_in_transit_quantity],
            at_platform: entry[:return_at_platform_quantity],
            unsellable: entry[:unsellable_quantity]
          }
        end
      end
    end
  end
end
```

`lib/tasks/ec_inventory_ledger.rake`:

```ruby
require "csv"

namespace :ec do
  namespace :inventory do
    desc "Compare legacy book stock with the book ledger for every SKU (read only), writes tmp/ledger_diff_*.csv"
    task ledger_diff: :environment do
      rows = Ec::Inventory::LedgerDiff.call(sku_codes: Ec::Sku.order(:sku_code).pluck(:sku_code))
      path = Rails.root.join("tmp", "ledger_diff_#{Time.current.strftime('%Y%m%d%H%M')}.csv")
      CSV.open(path, "w") do |csv|
        csv << %w[sku_code legacy ledger diff stale_open in_transit at_platform unsellable]
        rows.each { |row| csv << row.values_at(:sku_code, :legacy, :ledger, :diff, :stale_open, :in_transit, :at_platform, :unsellable) }
      end
      changed = rows.count { |row| row[:diff] != 0 }
      puts "skus=#{rows.size} changed=#{changed} sum_diff=#{rows.sum { |row| row[:diff] }} csv=#{path}"
      puts "unattributed (top 10): #{Ec::Inventory::BookLedger.unattributed.first(10).inspect}"
    end
  end
end
```

- [ ] **Step 4: Run to verify it passes**

Run: `bin/rails test test/services/ec/inventory/ledger_diff_test.rb`
Expected: 1 run, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add app/services/ec/inventory/ledger_diff.rb lib/tasks/ec_inventory_ledger.rake test/services/ec/inventory/ledger_diff_test.rb
git commit -m "Add book ledger shadow diff report"
```

---

### Task 7: WB statistics-only order backfill

**Files:**
- Modify: `app/services/ec/order_import/wb.rb`
- Create: `lib/tasks/ec_wb_orders.rake`
- Test: `test/services/ec/order_import/wb_stats_only_backfill_test.rb`

**Interfaces:**
- Produces: `Ec::OrderImport::Wb#import_unlinked_stats_only_orders(dry_run: false)` → Integer (orders imported, or would-be count when `dry_run`). It imports only `RawWb::StatsOrder` rows with a srid that have **no** `RawWb::StatsOrder` source link **and** no marketplace order (`raw_wb_orders`) with the same account and srid.

- [ ] **Step 1: Write the failing test**

```ruby
require "test_helper"
require "securerandom"

class Ec::OrderImport::WbStatsOnlyBackfillTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(4).upcase
    @account = RawWb::SellerAccount.create!(name: "wb-backfill-#{@token}", api_token: "t-#{@token}", company_type: "small")
    @store = Ec::Store.create!(
      platform: "wb", store_name: "WB Backfill #{@token}", company_type: "small",
      wb_raw_account_id: @account.id, is_active: true
    )
    @sku = Ec::Sku.create!(sku_code: "BACKFILL-#{@token}", product_name: "Backfill")
    @product = Ec::SkuProduct.create!(sku_code: @sku.sku_code, store: @store, product_id: "777#{@token.to_i(16) % 10_000}")
  end

  teardown do
    order_ids = Ec::Order.where(store_id: @store.id).select(:id)
    Ec::OrderSourceLink.where(order_id: order_ids).delete_all
    Ec::OrderItem.where(store_id: @store.id).delete_all
    Ec::OrderFulfillment.where(store_id: @store.id).delete_all
    Ec::Order.where(store_id: @store.id).delete_all
    RawWb::StatsOrder.where(account_id: @account.id).delete_all
    RawWb::Order.where(account_id: @account.id).delete_all
    Ec::SkuProduct.where(sku_code: @sku.sku_code).delete_all
    Ec::Store.where(id: @store.id).delete_all
    RawWb::SellerAccount.where(id: @account.id).delete_all
    Ec::Sku.with_deleted.where(id: @sku.id).delete_all
  end

  test "imports unlinked statistics orders that have no marketplace order and leaves covered ones alone" do
    stats_only = create_stats_order("ONLY-#{@token}", "Склад WB")
    covered = create_stats_order("COVERED-#{@token}", "Склад продавца")
    RawWb::Order.create!(
      account: @account, wb_order_id: 60_000_000_000 + @token.to_i(16), srid: covered.srid,
      nm_id: @product.product_id.to_i, delivery_type: "fbs", wb_status: "sold", supplier_status: "complete"
    )

    importer = Ec::OrderImport::Wb.new

    assert_equal 1, importer.import_unlinked_stats_only_orders(dry_run: true)
    assert_equal 0, Ec::Order.where(store_id: @store.id).count

    assert_equal 1, importer.import_unlinked_stats_only_orders
    order = Ec::Order.find_by!(store_id: @store.id)
    assert_equal stats_only.srid, order.external_order_id
    assert_equal "fbw", order.fulfillments.sole.fulfillment_type
    assert_equal 0, importer.import_unlinked_stats_only_orders
  end

  def create_stats_order(srid, warehouse_type)
    RawWb::StatsOrder.create!(
      account: @account, srid: srid, nm_id: @product.product_id.to_i, order_date: Time.zone.parse("2026-05-10 10:00:00"),
      warehouse_type: warehouse_type, warehouse_name: "Склад WB РФ", is_cancel: false,
      supplier_article: @sku.sku_code, synced_at: Time.zone.parse("2026-05-10 10:05:00")
    )
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `bin/rails test test/services/ec/order_import/wb_stats_only_backfill_test.rb`
Expected: ERROR `undefined method 'import_unlinked_stats_only_orders'`.

- [ ] **Step 3: Implement** — add to `Ec::OrderImport::Wb` (public section, above `private`)

```ruby
      # One-off backfill: statistics orders that were never turned into orders and are not covered by a
      # marketplace order (FBW orders). Idempotent: imported rows get a source link and drop out of the scope.
      def import_unlinked_stats_only_orders(dry_run: false)
        scope = unlinked_stats_only_scope
        return scope.count if dry_run

        total = 0
        scope.find_each { |stats_order| total += import_stats_order(stats_order) }
        total
      end
```

and in the private section:

```ruby
      def unlinked_stats_only_scope
        RawWb::StatsOrder.includes(:account)
          .where.not(srid: [ nil, "" ])
          .where.not(id: Ec::OrderSourceLink.where(source_type: "RawWb::StatsOrder").select(:source_id))
          .where(
            "NOT EXISTS (SELECT 1 FROM raw_wb_orders r " \
            "WHERE r.account_id = raw_wb_stats_orders.account_id AND r.srid = raw_wb_stats_orders.srid)"
          )
      end
```

`lib/tasks/ec_wb_orders.rake`:

```ruby
namespace :ec do
  namespace :wb_orders do
    desc "Import WB statistics orders that have no order yet and no marketplace order (dry run unless APPLY=1)"
    task import_unlinked_stats: :environment do
      apply = ENV["APPLY"] == "1"
      count = Ec::OrderImport::Wb.new.import_unlinked_stats_only_orders(dry_run: !apply)
      puts "#{apply ? 'imported' : 'would import'}: #{count}"
      puts "re-run with APPLY=1 to write" unless apply
    end
  end
end
```

- [ ] **Step 4: Run to verify it passes**

Run: `bin/rails test test/services/ec/order_import/wb_stats_only_backfill_test.rb`
Expected: 1 run, 0 failures. If `RawWb::StatsOrder.create!` rejects a missing required column, add that column to `create_stats_order` (the schema requires only `account_id` and `order_date`).

- [ ] **Step 5: Commit**

```bash
git add app/services/ec/order_import/wb.rb lib/tasks/ec_wb_orders.rake test/services/ec/order_import/wb_stats_only_backfill_test.rb
git commit -m "Add backfill for WB statistics-only orders"
```

---

### Task 7b: Order completeness check

**Files:**
- Create: `app/services/ec/inventory/order_completeness.rb`
- Create: `lib/tasks/ec_inventory_completeness.rake`
- Test: `test/services/ec/inventory/order_completeness_test.rb`

**Interfaces:**
- Produces: `Ec::Inventory::OrderCompleteness.call` → `{ wb_marketplace_orders_without_order:, wb_stats_orders_without_order:, ozon_postings_without_fulfillment: }` (Integers). All three must be 0 in a healthy system (spec 4.7).

- [ ] **Step 1: Write the failing test**

```ruby
require "test_helper"
require_relative "../../../support/book_ledger_fixtures"

class Ec::Inventory::OrderCompletenessTest < ActiveSupport::TestCase
  include BookLedgerFixtures

  setup { setup_ledger_world }
  teardown { teardown_ledger_world }

  test "counts raw orders and postings that never became orders" do
    before = Ec::Inventory::OrderCompleteness.call

    RawWb::Order.create!(
      account: @wb_account, wb_order_id: 71_000_000_000 + @token.to_i(16), nm_id: 1,
      delivery_type: "fbs", wb_status: "waiting", supplier_status: "new"
    )
    RawOzon::PostingFbs.create!(
      account: @ozon_account, posting_number: "NOFULFILL-#{@token}", status: "delivered",
      raw_json: {}, created_at: Time.current
    )

    after = Ec::Inventory::OrderCompleteness.call

    assert_equal before[:wb_marketplace_orders_without_order] + 1, after[:wb_marketplace_orders_without_order]
    assert_equal before[:ozon_postings_without_fulfillment] + 1, after[:ozon_postings_without_fulfillment]
    assert_equal before[:wb_stats_orders_without_order], after[:wb_stats_orders_without_order]
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `bin/rails test test/services/ec/inventory/order_completeness_test.rb`
Expected: ERROR `uninitialized constant Ec::Inventory::OrderCompleteness`.

- [ ] **Step 3: Implement**

```ruby
module Ec
  module Inventory
    # Raw platform orders that never reached ec_orders. A non-zero value means sales are missing from the ledger.
    class OrderCompleteness
      def self.call
        {
          wb_marketplace_orders_without_order: RawWb::Order
            .where.not(id: Ec::OrderSourceLink.where(source_type: "RawWb::Order").select(:source_id)).count,
          wb_stats_orders_without_order: RawWb::StatsOrder
            .where.not(srid: [ nil, "" ])
            .where.not(id: Ec::OrderSourceLink.where(source_type: "RawWb::StatsOrder").select(:source_id))
            .where(
              "NOT EXISTS (SELECT 1 FROM raw_wb_orders r " \
              "WHERE r.account_id = raw_wb_stats_orders.account_id AND r.srid = raw_wb_stats_orders.srid)"
            ).count,
          ozon_postings_without_fulfillment: ozon_postings_without_fulfillment(RawOzon::PostingFbs) +
            ozon_postings_without_fulfillment(RawOzon::PostingFbo)
        }
      end

      def self.ozon_postings_without_fulfillment(model)
        model.where(
          "NOT EXISTS (SELECT 1 FROM ec_order_fulfillments f " \
          "WHERE f.platform = 'ozon' AND f.external_fulfillment_id = #{model.table_name}.posting_number)"
        ).count
      end
      private_class_method :ozon_postings_without_fulfillment
    end
  end
end
```

`lib/tasks/ec_inventory_completeness.rake`:

```ruby
namespace :ec do
  namespace :inventory do
    desc "Report raw orders and postings that never became orders (read only)"
    task completeness: :environment do
      result = Ec::Inventory::OrderCompleteness.call
      result.each { |key, count| puts "#{key}: #{count}" }
      puts(result.values.all?(&:zero?) ? "OK" : "MISSING ORDERS")
    end
  end
end
```

- [ ] **Step 4: Run to verify it passes**

Run: `bin/rails test test/services/ec/inventory/order_completeness_test.rb`
Expected: 1 run, 0 failures. (If `RawOzon::PostingFbs` requires more columns, add them to the test row.)

- [ ] **Step 5: Commit**

```bash
git add app/services/ec/inventory/order_completeness.rb lib/tasks/ec_inventory_completeness.rake test/services/ec/inventory/order_completeness_test.rb
git commit -m "Add order completeness check for the book ledger"
```

---

> **Release 1 stops here.** Deploy, then run on production (read only first):
> `bin/rails ec:inventory:completeness`, `bin/rails ec:inventory:ledger_diff` and `bin/rails ec:wb_orders:import_unlinked_stats` (dry run). Check that every non-zero `diff` is explained by the spec section 2 problems and that `ReturnedToOzon` goods are not already inside the FBO stock snapshot (spec 12.3). Then run `APPLY=1 bin/rails ec:wb_orders:import_unlinked_stats` once and re-run the diff before starting Release 2.

---

### Task 8: Cut over `SkuInventoryOverviewBatchQuery`

**Files:**
- Modify: `app/services/ec/sku_inventory_overview_batch_query.rb`
- Test: `test/services/ec/sku_inventory_overview_batch_query_test.rb` (create)

**Interfaces:**
- Consumes: `Ec::Inventory::BookLedger.call(sku_codes:)`.
- Produces: unchanged shape `{ "SKU" => { book_stock:, platform_stock:, incoming_quantity: } }`, `book_stock` now `ledger_total`.

- [ ] **Step 1: Write the failing test**

```ruby
require "test_helper"
require_relative "../../support/book_ledger_fixtures"

class Ec::SkuInventoryOverviewBatchQueryTest < ActiveSupport::TestCase
  include BookLedgerFixtures

  setup { setup_ledger_world }
  teardown { teardown_ledger_world }

  test "book stock follows the ledger rules" do
    ledger_batch(50)
    ledger_order(platform: "wb", status: "delivered", quantity: 10)
    ledger_order(platform: "wb", status: "processing", quantity: 6, ordered_at: Time.current - 100.days)
    returned = ledger_order(platform: "ozon", status: "delivered", quantity: 4)
    ledger_return(returned, source_status: "ReceivedBySeller", quantity: 3)

    result = Ec::SkuInventoryOverviewBatchQuery.new(skus: [ @sku ]).call.fetch(@sku.sku_code)

    assert_equal 50 - 14 + 3, result[:book_stock]
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `bin/rails test test/services/ec/sku_inventory_overview_batch_query_test.rb`
Expected: FAIL — legacy value `50 - 20 + 0` (the stale order is deducted and the return is not restockable).

- [ ] **Step 3: Implement** — replace `call` and remove `received_quantities`, `sales_quantities`, `return_quantities`

```ruby
    def call
      return {} if @sku_codes.empty?

      ledger = Ec::Inventory::BookLedger.call(sku_codes: @sku_codes)
      incoming = incoming_quantities
      platform = platform_quantities

      @sku_codes.index_with do |sku_code|
        {
          book_stock: ledger.fetch(sku_code)[:ledger_total],
          platform_stock: platform.fetch(sku_code, 0),
          incoming_quantity: incoming.fetch(sku_code, 0)
        }
      end
    end
```

Also delete the now-unused constants `RECEIVED_STATUSES` and `ORDER_ITEM_JOIN` from the class.

- [ ] **Step 4: Run to verify it passes**

Run: `bin/rails test test/services/ec/sku_inventory_overview_batch_query_test.rb`
Expected: 1 run, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add app/services/ec/sku_inventory_overview_batch_query.rb test/services/ec/sku_inventory_overview_batch_query_test.rb
git commit -m "Compute batch book stock with the book ledger"
```

---

### Task 9: Cut over `InventoryTurnoverMetricsQuery` (historical snapshots)

**Files:**
- Modify: `app/services/ec/inventory_turnover_metrics_query.rb`
- Test: `test/services/ec/inventory_turnover_metrics_query_test.rb`

**Interfaces:**
- Consumes: `BookLedger.call(sku_codes:, as_of: cutoff_time)`.
- Produces: unchanged hash shape per SKU; `book_stock` is `ledger_total`.

- [ ] **Step 1: Write the failing test** (append to `inventory_turnover_metrics_query_test.rb`; reuse its `setup` helper names — if the file has none, add `include BookLedgerFixtures` plus `require_relative "../../support/book_ledger_fixtures"`)

```ruby
  test "book stock at a date follows the ledger rules" do
    setup_ledger_world
    ledger_batch(40, received_on: Date.new(2026, 9, 1))
    ledger_order(platform: "wb", status: "delivered", quantity: 5, ordered_at: Time.zone.parse("2026-09-05 10:00:00"))
    ledger_order(platform: "wb", status: "delivered", quantity: 8, ordered_at: Time.zone.parse("2026-09-20 10:00:00"))
    cancelled = ledger_order(platform: "ozon", status: "cancelled", quantity: 7,
                             ordered_at: Time.zone.parse("2026-09-06 10:00:00"))
    assert cancelled

    metrics = Ec::InventoryTurnoverMetricsQuery.new(
      sku_codes: [ @sku.sku_code ], date_to: Date.new(2026, 9, 15), time_zone: Time.find_zone!("Asia/Shanghai")
    ).call

    assert_equal 35, metrics.fetch(@sku.sku_code.upcase)[:book_stock]
  ensure
    teardown_ledger_world
  end
```

- [ ] **Step 2: Run to verify it fails**

Run: `bin/rails test test/services/ec/inventory_turnover_metrics_query_test.rb -n /ledger rules/`
Expected: FAIL (legacy formula has no per-order fulfillment status handling; also check the whole file for fixtures relying on `restockable`).

- [ ] **Step 3: Implement** — in `call`, replace the received/sales/returned computation

```ruby
      ledger = Ec::Inventory::BookLedger.call(sku_codes: @sku_codes, as_of: cutoff_time)
      procurement_quantities = procurement_quantities_by_sku

      @sku_codes.index_with do |sku_code|
        daily_sales_velocity = velocity_metrics.dig(sku_code, :daily_sales_velocity)
        book_stock = ledger.fetch(sku_code)[:ledger_total]
        procurement_stock = procurement_quantities.fetch(sku_code, 0)
        # (rest of the returned hash is unchanged)
```

Delete the private methods `received_quantities_by_sku`, `sales_quantities_by_sku`, `returned_quantities_by_sku`, `ozon_return_quantities_by_sku`, `wb_return_quantities_by_sku`, `merge_quantities_by_sku`, `order_item_sku_product_join_sql`, `ozon_return_sku_product_join_sql` and `wb_return_sku_product_join_sql`; keep `procurement_quantities_by_sku` and `cutoff_time`.

- [ ] **Step 4: Run to verify it passes and fix legacy fixtures**

Run: `bin/rails test test/services/ec/inventory_turnover_metrics_query_test.rb test/services/ec/inventory_snapshot_test.rb`
Expected: the new test passes. For any older test that fails because its returns have no `source_status`, set `source_status: "ReceivedBySeller"` (Ozon) or `"Выдано"` (WB) on the `Ec::Return` fixture; because a return now reverses a sale only through its platform status, not through `restockable`. For tests whose `processing`/`pending` orders are older than 45 days, set `ordered_at` to `Time.current - 2.days` or the status to `delivered`.

- [ ] **Step 5: Commit**

```bash
git add app/services/ec/inventory_turnover_metrics_query.rb test/services/ec/inventory_turnover_metrics_query_test.rb test/services/ec/inventory_snapshot_test.rb
git commit -m "Compute historical book stock with the book ledger"
```

---

### Task 10: Cut over `SkuInventoryOverview`

**Files:**
- Modify: `app/services/ec/sku_inventory_overview.rb`
- Test: `test/services/ec/sku_inventory_overview_test.rb`

**Interfaces:**
- Consumes: `BookLedger.call`, `BookLedger.compose`.
- Produces: `summary` keeps every old key (`book_stock` = `ledger_total`, `available_stock` = `own_side`, `platform_stock` = all latest levels, `sales_quantity` = gross sales, `return_quantity` = reversed by returns) and adds `ledger_total, platform_sellable, platform_inbound, platform_side, own_side, return_in_transit, return_at_platform, unsellable, sellable, stale_open_order_quantity`. `store_rows` keep their shape; `sales_quantity`/`return_quantity`/`order_status_counts` come from the ledger's `by_store`.

- [ ] **Step 1: Update the existing tests and add the new one**

In `test/services/ec/sku_inventory_overview_test.rb`:

1. In `setup`, give the two fixture returns a platform status — the `@wb_return` creation gets `source_status: "Выдано"` and the `@ozon_return` creation gets `source_status: "ReceivedBySeller"`.
2. Replace the test `"reflects restockable changes immediately without cached inventory values"` with:

```ruby
  test "reflects return status changes immediately without cached inventory values" do
    assert_equal 3, @sku.inventory_overview.dig(:summary, :return_quantity)

    @ozon_return.update!(source_status: "Rejected")

    assert_equal 1, @sku.inventory_overview.dig(:summary, :return_quantity)
    assert_equal 6, @sku.inventory_overview.dig(:summary, :book_stock)
  end
```

3. Replace `"continues deducting returned WB FBS and Ozon orders"` with:

```ruby
  test "reverses returned WB orders but keeps Ozon orders with a returned status as sales" do
    @wb_fbs_order.update!(order_status: "returned")
    @wb_fbs_order.fulfillments.update_all(status: "returned")
    @ozon_order.update!(order_status: "returned")

    summary = @sku.inventory_overview[:summary]

    assert_equal 14, summary[:sales_quantity]
    assert_equal 2, summary[:return_quantity]
    assert_equal 14, summary[:book_stock]
  end
```

4. Replace `"continues deducting returned WB orders with unknown fulfillment"` with:

```ruby
  test "does not count returned WB orders with unknown fulfillment as sales" do
    order = Ec::Order.create!(
      platform: "wb", store: @wb_store,
      order_key: "WB-UNKNOWN-RETURNED-#{@token}",
      order_status: "returned"
    )
    order.items.create!(
      platform: "wb", store: @wb_store,
      platform_sku_id: @wb_sku_product.product_id,
      quantity: 2
    )

    assert_equal 21, @sku.inventory_overview.dig(:summary, :sales_quantity)
  end
```

5. In every existing test of this file that changes an order's status with `update!(order_status: ...)` (search for it, e.g. `"does not deduct returned WB FBW orders or add their return items"`), also set the fulfillment status, because the ledger reads the fulfillment status first: add `@wb_fbw_order.fulfillments.update_all(status: "returned")` right after `@wb_fbw_order.update!(order_status: "returned")`, and the same pattern for any other order changed this way. Expected numbers in that test (sales 16, return 3, book 13) stay valid.
6. In `"captures order status quantity buckets per store"` set `ordered_at: Time.current - 2.days` on both orders created there (instead of the 2026-06 timestamps) so they are not stale.
7. Add:

```ruby
  test "exposes the ledger split next to the legacy keys" do
    summary = @sku.inventory_overview[:summary]

    assert_equal summary[:book_stock], summary[:ledger_total]
    assert_equal summary[:available_stock], summary[:own_side]
    assert_equal 10, summary[:platform_sellable]
    assert_equal 2, summary[:platform_inbound]
    assert_equal 12, summary[:platform_side]
    assert_equal 0, summary[:stale_open_order_quantity]
    assert_equal summary[:platform_sellable] + summary[:own_side], summary[:sellable]
  end
```

- [ ] **Step 2: Run to verify the new/changed tests fail**

Run: `bin/rails test test/services/ec/sku_inventory_overview_test.rb`
Expected: FAIL on the changed tests (legacy formula) and `exposes the ledger split` (keys missing).

- [ ] **Step 3: Implement** — in `sku_inventory_overview.rb`

Replace `summary` with:

```ruby
    def summary(store_rows, latest_levels)
      seller_received_removals = store_rows.sum { |row| row[:ozon_seller_received_removal_quantity] }
      supply = store_rows.sum { |row| row[:supply_quantity] }
      platform_stock = latest_levels.sum(&:quantity)
      platform_inbound_stock = latest_levels
        .select { |level| level.fulfillment_type.to_s == "inbound" }
        .sum(&:quantity)
      fbo_fbw_stock = latest_levels
        .select { |level| level.fulfillment_type.to_s.in?(%w[fbo fbw]) }
        .sum(&:quantity)
      composed = Ec::Inventory::BookLedger.compose(
        ledger, platform_sellable: fbo_fbw_stock, platform_inbound: platform_inbound_stock
      )

      {
        purchase_quantity: ledger[:purchase_quantity],
        adjustment_quantity: ledger[:adjustment_quantity],
        received_quantity: ledger[:received_quantity],
        sales_quantity: ledger[:gross_sales_quantity],
        return_quantity: ledger[:reversed_quantity],
        ozon_seller_received_removal_quantity: seller_received_removals,
        supply_quantity: supply,
        platform_stock: platform_stock,
        platform_inbound_stock: platform_inbound_stock,
        fbo_fbw_stock: fbo_fbw_stock,
        book_stock: composed[:ledger_total],
        available_stock: composed[:own_side],
        ledger_total: composed[:ledger_total],
        platform_sellable: composed[:platform_sellable],
        platform_inbound: composed[:platform_inbound],
        platform_side: composed[:platform_side],
        own_side: composed[:own_side],
        return_in_transit: composed[:return_in_transit_quantity],
        return_at_platform: composed[:return_at_platform_quantity],
        unsellable: composed[:unsellable_quantity],
        sellable: composed[:sellable],
        stale_open_order_quantity: composed[:stale_open_order_quantity]
      }
    end

    def ledger
      @ledger ||= Ec::Inventory::BookLedger.call(sku_codes: [ @sku.sku_code ]).fetch(@sku.sku_code.upcase)
    end

    def ledger_stores
      @ledger_stores ||= Ec::Store.where(id: ledger[:by_store].keys.map(&:last)).index_by(&:id)
    end

    def ledger_store_key(platform, store)
      account_id = platform == "wb" ? store.wb_raw_account_id : store.ozon_raw_account_id
      key_for(platform, store.id, store.store_name, account_id)
    end
```

Delete `batch_summary`. Replace `order_rows` and `return_rows`:

```ruby
    def order_rows
      @order_rows ||= begin
        rows = Hash.new { |hash, key| hash[key] = { sales_quantity: 0, order_status_counts: empty_order_status_counts } }
        ledger[:by_store].each do |(platform, store_id), data|
          store = ledger_stores[store_id]
          next unless store

          current = rows[ledger_store_key(platform, store)]
          current[:sales_quantity] += data[:gross_sales_quantity]
          data[:status_counts].each { |bucket, quantity| current[:order_status_counts][bucket] += quantity }
        end
        rows
      end
    end

    def return_rows
      @return_rows ||= begin
        rows = Hash.new(0)
        ledger[:by_store].each do |(platform, store_id), data|
          store = ledger_stores[store_id]
          next unless store && data[:reversed_quantity].positive?

          rows[ledger_store_key(platform, store)] += data[:reversed_quantity]
        end
        rows
      end
    end
```

Delete `order_item_sku_product_join_sql` and `bucket_for_order_status` (no longer used). Keep the Ozon removal, supply and `key_for` methods.

- [ ] **Step 4: Run to verify they pass**

Run: `bin/rails test test/services/ec/sku_inventory_overview_test.rb test/services/ec/sku_inventory_overview_batch_query_test.rb test/services/ec/inventory_page_row_query_test.rb test/services/ec/inventory_page_detail_query_test.rb`
Expected: all pass. If `"batch overview matches detail overview inventory values"` fails, both sides must come from the ledger: re-check Tasks 8 and 10.

- [ ] **Step 5: Commit**

```bash
git add app/services/ec/sku_inventory_overview.rb test/services/ec/sku_inventory_overview_test.rb
git commit -m "Compute the SKU inventory overview with the book ledger"
```

---

### Task 11: Remove legacy scopes and the shadow tooling

**Files:**
- Modify: `app/models/ec/return_item.rb`
- Delete: `app/services/ec/inventory/ledger_diff.rb`, `lib/tasks/ec_inventory_ledger.rake`, `test/services/ec/inventory/ledger_diff_test.rb`

**Interfaces:**
- Removes: `Ec::ReturnItem.restockable_for_book_inventory`, `Ec::Inventory::LedgerDiff`. **Keeps** `Ec::OrderItem.deductible_from_book_inventory` because `Ec::InventoryOrderSalesDistributionQuery` (order distribution, physical stocktake) still uses it.

- [ ] **Step 1: Verify nothing else uses the scope**

Run: `grep -rn "restockable_for_book_inventory\|LedgerDiff" app lib test`
Expected: only the definitions and the files deleted below.

- [ ] **Step 2: Delete the shadow tooling and the scope**

```bash
git rm app/services/ec/inventory/ledger_diff.rb lib/tasks/ec_inventory_ledger.rake test/services/ec/inventory/ledger_diff_test.rb
```

In `app/models/ec/return_item.rb` remove the whole `scope :restockable_for_book_inventory, -> { ... }` block, keeping `scope :restockable`.

- [ ] **Step 3: Run the inventory test set**

Run: `bin/rails test test/services/ec test/models/ec test/i18n`
Expected: no new failures compared with before this task. Pre-existing failures (leftover non-transactional data, date-dependent WB sync tests) are not caused by this change.

- [ ] **Step 4: Commit**

```bash
git add app/models/ec/return_item.rb
git commit -m "Remove legacy book inventory return scope and shadow tooling"
```

---

### Task 12: Trend note, labels and reference document

**Files:**
- Modify: `app/services/ec/inventory/book_ledger.rb` (constant)
- Modify: `app/views/reports/_sku_inventory_trend.html.erb`
- Modify: `config/locales/zh.yml`, `config/locales/en.yml`, `config/locales/ru.yml`
- Modify: `docs/库存计算260615.md`
- Test: `test/services/ec/inventory/book_ledger_test.rb`

**Interfaces:**
- Produces: `Ec::Inventory::BookLedger::EFFECTIVE_ON` (Date). Set it to the date Release 2 is deployed.

- [ ] **Step 1: Write the failing test**

```ruby
  test "exposes the date the ledger rules took effect" do
    assert_kind_of Date, Ec::Inventory::BookLedger::EFFECTIVE_ON
  end
```

- [ ] **Step 2: Run to verify it fails**

Run: `bin/rails test test/services/ec/inventory/book_ledger_test.rb -n /took effect/`
Expected: ERROR `uninitialized constant ...EFFECTIVE_ON`.

- [ ] **Step 3: Implement**

In `book_ledger.rb`, next to `STALE_OPEN_ORDER_DAYS`:

```ruby
      # First day snapshots use the ledger rules. Earlier persisted snapshots keep the old formula.
      EFFECTIVE_ON = Date.new(2026, 10, 14)
```

In `_sku_inventory_trend.html.erb`, directly after the closing `</table>` inside the `<%= table_viewport ... do %>` block's following line (i.e. still inside `if show_table`), add:

```erb
    <% if trend[:weeks].any? { |row| row[:snapshot_date].present? && row[:snapshot_date].to_s < Ec::Inventory::BookLedger::EFFECTIVE_ON.iso8601 } %>
      <p class="muted"><%= t("reports.inventory.trend.ledger_rules_note", date: Ec::Inventory::BookLedger::EFFECTIVE_ON.iso8601) %></p>
    <% end %>
```

Locales — under `reports.inventory.trend` add the key `ledger_rules_note` (next to `metrics:`):

- zh: `ledger_rules_note: "账面库存口径自 %{date} 起调整，此日期之前的快照沿用旧口径，不可与之后的数值直接比较。"`
- en: `ledger_rules_note: "Book stock rules changed on %{date}; earlier snapshots keep the old formula and are not directly comparable."`
- ru: `ledger_rules_note: "Правила учётного остатка изменены %{date}; более ранние снимки используют прежнюю формулу и несопоставимы."`

Rename the label of key `reports.inventory.fields.overseas_available_stock` (currently shown as the FBS stock column): zh `"自有侧库存（推算）"`, en `"Own-side stock (derived)"`, ru `"Остаток на стороне продавца (расчётный)"`.

Append to `docs/库存计算260615.md`:

```markdown

---

## 2026-10 口径调整

账面库存改由 `Ec::Inventory::BookLedger` 统一计算（见 `docs/superpowers/specs/2026-10-12-book-inventory-ledger-design.md`）：

- 总量 = 入库（不含物理盘库矫正）− 净销量；净销量不含取消单、WB `returned` 订单、被退货冲销的销量，以及下单超过 45 天仍是 `pending/processing` 的订单。
- 平台侧 = FBO/FBW 库存快照 + 入库中；自有侧 = 总量 − 平台侧（推算）。
- 可售 = 平台可售 + 自有侧 − 在途退货 − 平台退货仓 − 不可售。
- 历史快照不回填，趋势页在口径变更日加标注。
```

- [ ] **Step 4: Run to verify it passes**

Run: `bin/rails test test/services/ec/inventory/book_ledger_test.rb test/i18n`
Expected: pass. (Locale parity is checked by `test/i18n`.)

- [ ] **Step 5: Commit** — stage only your hunks in the three locale files (see Global Constraints)

```bash
git add app/services/ec/inventory/book_ledger.rb app/views/reports/_sku_inventory_trend.html.erb docs/库存计算260615.md test/services/ec/inventory/book_ledger_test.rb
git apply --cached <patch containing only your locale hunks, built as described in Global Constraints>
git commit -m "Annotate the trend with the book ledger effective date and rename the own-side label"
```

---

### Task 13: Extend the WB status refresh lookback

**Files:**
- Modify: `app/services/raw_wb/syncs/orders.rb:6`

**Interfaces:**
- Changes: `RawWb::Syncs::Orders::DEFAULT_ORDER_STATUS_LOOKBACK_DAYS` from 90 to 180 so non-final WB orders created in the last 180 days are re-polled. The ledger already ignores open orders older than 45 days, so this only reduces stale raw data.

- [ ] **Step 1: Make the change**

```ruby
      DEFAULT_ORDER_STATUS_LOOKBACK_DAYS = 180
```

- [ ] **Step 2: Check there is no test pinning the old value**

Run: `grep -rn "LOOKBACK_DAYS\|90.days" test/services/raw_wb test/jobs | head`
Expected: no assertions on 90 days. Update any that exist.

- [ ] **Step 3: Run the WB sync tests**

Run: `bin/rails test test/services/raw_wb`
Expected: no new failures.

- [ ] **Step 4: Commit**

```bash
git add app/services/raw_wb/syncs/orders.rb
git commit -m "Re-poll non-final WB order statuses for 180 days"
```

Note: WB's status endpoint behavior for very old orders was not verified. After deploy, check the sync log once for errors; if the endpoint rejects old ids, revert this task — the ledger rules do not depend on it.

---

### Task 14: Final verification and release notes

**Files:**
- Test: whole inventory-related suite

- [ ] **Step 1: Run the affected suites**

Run:

```bash
bin/rails test test/services/ec/inventory test/services/ec/sku_inventory_overview_test.rb test/services/ec/sku_inventory_overview_batch_query_test.rb test/services/ec/inventory_turnover_metrics_query_test.rb test/services/ec/inventory_snapshot_test.rb test/services/ec/inventory_page_row_query_test.rb test/services/ec/inventory_page_detail_query_test.rb test/services/ec/inventory_physical_reconciliation_query_test.rb test/services/ec/order_import test/i18n
```

Expected: all pass.

- [ ] **Step 2: Run the consumer tests and triage**

Run:

```bash
bin/rails test test/controllers/operator_skus_controller_test.rb test/controllers/ai test/services/erp_ai test/services/ec/inventory_capital_distribution_query_test.rb test/services/ec/sku_inventory_trend_query_test.rb test/services/ec/inventory_volume_summary_builder_test.rb
```

For each failure decide: (a) a fixture relies on `restockable` or on an old `processing` order: adjust the fixture as in Task 9 step 4; (b) a pre-existing failure from leftover data: leave. Do not change production code to satisfy a stale fixture.

- [ ] **Step 3: Release 2 checklist (do not automate)**

1. Set `BookLedger::EFFECTIVE_ON` to the deploy date and commit.
2. Deploy; open the inventory list and one SKU drawer; confirm `book_stock` equals `ledger_total` and `available_stock` equals `own_side`.
3. Confirm the next daily snapshot (`Ec::SnapshotRunner`, 03:00 Asia/Shanghai) runs without error and its `book_stock` matches the live value for a sample SKU.
4. Do not backfill `ec_snapshots`.

- [ ] **Step 4: Commit** (only if Step 2 changed fixtures)

```bash
git add <changed test files>
git commit -m "Adjust inventory consumer fixtures to the book ledger rules"
```
