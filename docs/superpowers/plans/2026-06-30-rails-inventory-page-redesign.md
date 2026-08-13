# Rails Inventory Page Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current `/reports/inventory` table page with a Rails/Turbo inventory workspace that uses a searchable SKU list plus a Turbo drawer detail surface built from real inventory, batch, and platform data.

**Architecture:** Keep `Ec::SkuInventoryOverview` as the stable formula source, add page-facing query objects for inventory index rows and drawer detail payloads, and render the new UI through ERB partials plus a reusable Turbo overlay pattern. The drawer should load through a dedicated frame route so tab switching and pagination remain URL-driven and server-rendered.

**Tech Stack:** Rails 8, ERB, Turbo, Stimulus, ActiveRecord, Minitest, I18n, application.css

---

### Task 1: Lock The New Inventory Page Contract In Controller Tests

**Files:**
- Modify: `test/controllers/reports_controller_test.rb`
- Test: `test/controllers/reports_controller_test.rb`

- [ ] **Step 1: Write the failing inventory index test for the redesigned page**

Add a new integration test near the existing inventory report tests that asserts the page now renders:

- a `turbo-frame#inventory_drawer`
- summary/list columns for `待入库库存`, `账面可用库存`, `平台在库`, `境外当前可用`
- a detail action or row link targeting `/reports/inventory/:sku_code`

Use assertions shaped like:

```ruby
test "inventory report renders redesigned inventory workspace" do
  Ec::SkuBatch.create!(
    sku_code: @sku.sku_code,
    batch_code: "REDESIGN-#{@sku_code}",
    status: "received",
    batch_type: :normal,
    purchased_quantity: 24,
    received_quantity: 24,
    purchase_unit_price_cny: 1
  )
  Ec::SkuBatch.create!(
    sku_code: @sku.sku_code,
    batch_code: "INCOMING-#{@sku_code}",
    status: "in_transit",
    batch_type: :normal,
    purchased_quantity: 8,
    received_quantity: 0,
    expected_arrival_on: Date.new(2026, 7, 10),
    purchase_unit_price_cny: 1
  )
  Ec::SkuInventoryLevel.create!(
    sku_code: @sku.sku_code,
    platform: "ozon",
    account_id: @sales_ozon_account.id,
    store_name: @sales_store.store_name,
    store: @sales_store,
    fulfillment_type: "fbo",
    quantity: 4,
    is_latest: true,
    synced_at: Time.zone.parse("2026-06-22 10:00:00"),
    metadata: {}
  )

  get "/reports/inventory", headers: { "Accept" => "text/html" }

  assert_response :success
  assert_select "h1", "库存报表"
  assert_select "turbo-frame#inventory_drawer"
  assert_select "th", "待入库库存"
  assert_select "th", "账面可用库存"
  assert_select "th", "平台在库"
  assert_select "th", "境外当前可用"
  assert_select "a[href=?][data-turbo-frame=?]", "/reports/inventory/#{@sku_code}", "inventory_drawer"
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
SKIP_JS_BUILD=1 bundle exec ruby bin/rails test test/controllers/reports_controller_test.rb -n "/redesigned inventory workspace/"
```

Expected: FAIL because the current page still renders the old table structure and no `inventory_drawer` frame exists.

- [ ] **Step 3: Write the failing drawer test**

Add a second test for the detail route:

```ruby
test "inventory detail renders turbo drawer content" do
  Ec::SkuBatch.create!(
    sku_code: @sku.sku_code,
    batch_code: "DRAWER-#{@sku_code}",
    status: "received",
    batch_type: :normal,
    purchased_quantity: 12,
    received_quantity: 12,
    purchase_unit_price_cny: 1
  )

  get "/reports/inventory/#{@sku_code}",
      params: { detail_tab: "incoming" },
      headers: { "Accept" => "text/html", "Turbo-Frame" => "inventory_drawer" }

  assert_response :success
  assert_select "turbo-frame#inventory_drawer"
  assert_select "[role='dialog']"
  assert_select "h2", @sku_code
  assert_select "h3", "概览"
  assert_select "h4", "待入库批次"
end
```

- [ ] **Step 4: Run the drawer test to verify it fails**

Run:

```bash
SKIP_JS_BUILD=1 bundle exec ruby bin/rails test test/controllers/reports_controller_test.rb -n "/inventory detail renders turbo drawer content/"
```

Expected: FAIL because the route and view do not exist yet.

- [ ] **Step 5: Commit the red tests**

```bash
git add test/controllers/reports_controller_test.rb
git commit -m "test: define redesigned inventory page contract"
```

### Task 2: Add Page-Facing Query Objects For Inventory Index And Drawer Data

**Files:**
- Create: `app/services/ec/inventory_page_row_query.rb`
- Create: `app/services/ec/inventory_page_detail_query.rb`
- Create: `test/services/ec/inventory_page_row_query_test.rb`
- Create: `test/services/ec/inventory_page_detail_query_test.rb`

- [ ] **Step 1: Write the failing row query test**

Create `test/services/ec/inventory_page_row_query_test.rb` with coverage for:

- `incoming_quantity` from batch statuses `draft`, `ordered`, `in_transit`
- `book_stock` from `Ec::SkuInventoryOverview[:summary][:book_stock]`
- `platform_stock` from `Ec::SkuInventoryOverview[:summary][:platform_stock]`
- `available_stock` from `Ec::SkuInventoryOverview[:summary][:available_stock]`

Use a shape like:

```ruby
require "test_helper"

class Ec::InventoryPageRowQueryTest < ActiveSupport::TestCase
  test "builds redesigned inventory list row from real sku data" do
    token = SecureRandom.hex(4).upcase
    sku = Ec::Sku.create!(sku_code: "ROW-#{token}", product_name: "行测试商品")

    Ec::SkuBatch.create!(
      sku_code: sku.sku_code,
      batch_code: "ROW-REC-#{token}",
      status: "received",
      batch_type: :normal,
      purchased_quantity: 20,
      received_quantity: 20,
      purchase_unit_price_cny: 1
    )
    Ec::SkuBatch.create!(
      sku_code: sku.sku_code,
      batch_code: "ROW-IT-#{token}",
      status: "in_transit",
      batch_type: :normal,
      purchased_quantity: 7,
      received_quantity: 0,
      purchase_unit_price_cny: 1
    )

    row = Ec::InventoryPageRowQuery.new(sku).call

    assert_equal 7, row[:incoming_quantity]
    assert_equal sku.sku_code, row[:sku_code]
    assert_equal "行测试商品", row[:product_name]
    assert_includes row.keys, :book_stock
    assert_includes row.keys, :platform_stock
    assert_includes row.keys, :available_stock
  ensure
    Ec::SkuBatch.where(sku_code: sku&.sku_code).delete_all
    Ec::Sku.with_deleted.where(sku_code: sku&.sku_code).delete_all
  end
end
```

- [ ] **Step 2: Run the row query test to verify it fails**

Run:

```bash
SKIP_JS_BUILD=1 bundle exec ruby bin/rails test test/services/ec/inventory_page_row_query_test.rb
```

Expected: FAIL because the query class does not exist yet.

- [ ] **Step 3: Write the failing detail query test**

Create `test/services/ec/inventory_page_detail_query_test.rb` that asserts:

- `incoming_batches` comes from `ec_sku_batches` with `draft`, `ordered`, `in_transit`
- `book_batches` comes from `ec_sku_batches` with `received`, `closed`
- `platform_breakdown` comes from latest `Ec::SkuInventoryLevel`
- `summary` reuses `sku.inventory_overview[:summary]`

Use a shape like:

```ruby
require "test_helper"

class Ec::InventoryPageDetailQueryTest < ActiveSupport::TestCase
  test "builds drawer payload from overview batches and latest levels" do
    token = SecureRandom.hex(4).upcase
    sku = Ec::Sku.create!(sku_code: "DETAIL-#{token}", product_name: "详情测试商品")

    incoming = Ec::SkuBatch.create!(
      sku_code: sku.sku_code,
      batch_code: "DETAIL-IN-#{token}",
      status: "in_transit",
      batch_type: :normal,
      purchased_quantity: 9,
      received_quantity: 0,
      expected_arrival_on: Date.new(2026, 7, 20),
      purchase_unit_price_cny: 1
    )
    book = Ec::SkuBatch.create!(
      sku_code: sku.sku_code,
      batch_code: "DETAIL-BOOK-#{token}",
      status: "received",
      batch_type: :wb_fbw_offset,
      purchased_quantity: 0,
      received_quantity: -2,
      defect_offset_note: "WB offset",
      purchase_unit_price_cny: 1
    )
    Ec::SkuInventoryLevel.create!(
      sku_code: sku.sku_code,
      platform: "wb",
      account_id: 1,
      store_name: "WB 店铺 #{token}",
      fulfillment_type: "fbw",
      quantity: 5,
      is_latest: true,
      synced_at: Time.zone.parse("2026-06-25 10:00:00"),
      metadata: {}
    )

    payload = Ec::InventoryPageDetailQuery.new(sku, detail_tab: "book", book_batch_page: 1).call

    assert_equal sku.sku_code, payload[:sku_code]
    assert_equal "book", payload[:active_detail_tab]
    assert_equal [incoming.batch_code], payload[:incoming_batches].map { |row| row[:batch_code] }
    assert_equal [book.batch_code], payload[:book_batches].map { |row| row[:batch_code] }
    assert_equal 5, payload[:platform_breakdown].sum { |row| row[:quantity] }
    assert_includes payload[:summary].keys, :book_stock
  ensure
    Ec::SkuInventoryLevel.where(sku_code: sku&.sku_code).delete_all
    Ec::SkuBatch.where(sku_code: sku&.sku_code).delete_all
    Ec::Sku.with_deleted.where(sku_code: sku&.sku_code).delete_all
  end
end
```

- [ ] **Step 4: Run the detail query test to verify it fails**

Run:

```bash
SKIP_JS_BUILD=1 bundle exec ruby bin/rails test test/services/ec/inventory_page_detail_query_test.rb
```

Expected: FAIL because the detail query class does not exist yet.

- [ ] **Step 5: Implement the minimal row query**

Create `app/services/ec/inventory_page_row_query.rb`:

```ruby
module Ec
  class InventoryPageRowQuery
    INCOMING_STATUSES = %w[draft ordered in_transit].freeze

    def initialize(sku)
      @sku = sku
    end

    def call
      summary = @sku.inventory_overview[:summary]

      {
        sku_code: @sku.sku_code,
        product_name: @sku.product_name,
        product_name_ru: @sku.product_name_ru,
        incoming_quantity: incoming_quantity,
        book_stock: summary[:book_stock],
        platform_stock: summary[:platform_stock],
        available_stock: summary[:available_stock]
      }
    end

    private

    def incoming_quantity
      @sku.batches.where(status: INCOMING_STATUSES).sum(:purchased_quantity).to_i
    end
  end
end
```

- [ ] **Step 6: Implement the minimal detail query**

Create `app/services/ec/inventory_page_detail_query.rb`:

```ruby
module Ec
  class InventoryPageDetailQuery
    INCOMING_STATUSES = %w[draft ordered in_transit].freeze
    BOOK_STATUSES = %w[received closed].freeze
    BOOK_BATCH_PAGE_SIZE = 10

    def initialize(sku, detail_tab:, book_batch_page:)
      @sku = sku
      @detail_tab = detail_tab.presence_in(%w[incoming book platform]) || "incoming"
      @book_batch_page = [book_batch_page.to_i, 1].max
    end

    def call
      overview = @sku.inventory_overview
      book_batches = book_batches_scope

      {
        sku_code: @sku.sku_code,
        product_name: @sku.product_name,
        product_name_ru: @sku.product_name_ru,
        active_detail_tab: @detail_tab,
        summary: overview[:summary],
        incoming_quantity: incoming_batches.sum { |row| row[:purchased_quantity].to_i },
        incoming_batches: incoming_batches,
        book_batches: paginate_book_batches(book_batches),
        book_batch_pagination: book_batch_pagination(book_batches.count),
        store_reconciliation_rows: overview[:store_rows],
        platform_breakdown: platform_breakdown
      }
    end

    private

    def incoming_batches
      @incoming_batches ||= @sku.batches
        .where(status: INCOMING_STATUSES)
        .order(expected_arrival_on: :asc, batch_code: :asc)
        .map do |batch|
          {
            batch_code: batch.batch_code,
            status: batch.status,
            expected_arrival_on: batch.expected_arrival_on,
            purchased_quantity: batch.purchased_quantity,
            memo: batch.memo
          }
        end
    end

    def book_batches_scope
      @sku.batches.where(status: BOOK_STATUSES).order(received_on: :desc, batch_code: :desc)
    end

    def paginate_book_batches(scope)
      scope.limit(BOOK_BATCH_PAGE_SIZE).offset((@book_batch_page - 1) * BOOK_BATCH_PAGE_SIZE).map do |batch|
        {
          batch_code: batch.batch_code,
          batch_type: batch.batch_type,
          defect_offset_note: batch.defect_offset_note,
          received_quantity: batch.received_quantity,
          received_on: batch.received_on,
          status: batch.status
        }
      end
    end

    def book_batch_pagination(total_count)
      total_pages = (total_count / BOOK_BATCH_PAGE_SIZE.to_f).ceil

      {
        page: @book_batch_page,
        page_size: BOOK_BATCH_PAGE_SIZE,
        total_count: total_count,
        total_pages: [total_pages, 1].max
      }
    end

    def platform_breakdown
      @sku.inventory_levels.latest.order(:platform, :store_name, :fulfillment_type).map do |level|
        {
          platform: level.platform,
          fulfillment_type: level.fulfillment_type,
          store_id: level.store_id,
          store_name: level.store_name,
          account_id: level.account_id,
          quantity: level.quantity,
          latest_synced_at: level.synced_at
        }
      end
    end
  end
end
```

- [ ] **Step 7: Run the new service tests to verify they pass**

Run:

```bash
SKIP_JS_BUILD=1 bundle exec ruby bin/rails test test/services/ec/inventory_page_row_query_test.rb test/services/ec/inventory_page_detail_query_test.rb
```

Expected: PASS

- [ ] **Step 8: Commit the query objects**

```bash
git add app/services/ec/inventory_page_row_query.rb app/services/ec/inventory_page_detail_query.rb test/services/ec/inventory_page_row_query_test.rb test/services/ec/inventory_page_detail_query_test.rb
git commit -m "feat: add inventory page query objects"
```

### Task 3: Add Routes And Controller Endpoints For Turbo Drawer Rendering

**Files:**
- Modify: `config/routes.rb`
- Modify: `app/controllers/reports_controller.rb`
- Test: `test/controllers/reports_controller_test.rb`

- [ ] **Step 1: Add the failing route/controller expectations if still needed**

If the earlier controller tests do not already assert it, add assertions for:

- `GET /reports/inventory/:sku_code`
- Turbo Frame rendering
- non-frame fallback redirect

- [ ] **Step 2: Implement the routes**

Update `config/routes.rb`:

```ruby
get "reports/inventory" => "reports#inventory"
get "reports/inventory/:sku_code" => "reports#inventory_detail", as: :report_inventory_detail
post "reports/inventory/:sku_code/refresh_cache" => "reports#refresh_inventory_cache", as: :refresh_report_inventory_cache
```

- [ ] **Step 3: Implement the controller actions with minimal page assembly**

In `app/controllers/reports_controller.rb`, add:

```ruby
def inventory
  @sku_query = params[:sku].to_s.strip
  @inventory_rows = build_inventory_rows
end

def inventory_detail
  @sku = Ec::Sku.find_by!(sku_code: params[:sku_code].to_s.upcase)
  @inventory_detail = Ec::InventoryPageDetailQuery.new(
    @sku,
    detail_tab: params[:detail_tab],
    book_batch_page: params[:book_batch_page]
  ).call

  unless turbo_frame_request?
    redirect_to report_sku_path(@sku.sku_code, tab: "inventory")
    return
  end

  render :inventory_detail
end
```

Update the row builder path:

```ruby
def build_inventory_rows
  inventory_skus_scope.order(:sku_code).map do |sku|
    fetch_inventory_row(sku)
  end
end

def build_inventory_row(sku)
  Ec::InventoryPageRowQuery.new(sku).call
end
```

- [ ] **Step 4: Run the controller tests covering the new routes**

Run:

```bash
SKIP_JS_BUILD=1 bundle exec ruby bin/rails test test/controllers/reports_controller_test.rb -n "/inventory report renders redesigned inventory workspace|inventory detail renders turbo drawer content/"
```

Expected: still FAIL on missing templates/views, but route and redirect behavior should now be wired.

- [ ] **Step 5: Commit the controller and route changes**

```bash
git add config/routes.rb app/controllers/reports_controller.rb test/controllers/reports_controller_test.rb
git commit -m "feat: add inventory detail drawer endpoint"
```

### Task 4: Build A Reusable Turbo Drawer Shell And Inventory ERB Partials

**Files:**
- Create: `app/views/shared/_overlay_drawer.html.erb`
- Create: `app/views/reports/_inventory_drawer.html.erb`
- Create: `app/views/reports/_inventory_summary_cards.html.erb`
- Create: `app/views/reports/_inventory_incoming_batches.html.erb`
- Create: `app/views/reports/_inventory_book_inventory.html.erb`
- Create: `app/views/reports/_inventory_platform_breakdown.html.erb`
- Create: `app/views/reports/inventory_detail.html.erb`
- Modify: `app/views/reports/inventory.html.erb`
- Modify: `app/views/layouts/application.html.erb` only if a globally-mounted frame is necessary

- [ ] **Step 1: Implement the shared drawer shell partial**

Create `app/views/shared/_overlay_drawer.html.erb`:

```erb
<div class="erp-drawer-backdrop" data-controller="modal" data-action="click->modal#closeOnBackdrop">
  <section
    class="erp-drawer"
    role="dialog"
    aria-modal="true"
    aria-labelledby="<%= local_assigns.fetch(:title_id) %>">
    <div class="erp-drawer__header">
      <div>
        <% if local_assigns[:eyebrow].present? %>
          <p class="erp-drawer__eyebrow"><%= local_assigns[:eyebrow] %></p>
        <% end %>
        <h2 id="<%= local_assigns.fetch(:title_id) %>"><%= local_assigns.fetch(:title) %></h2>
        <% if local_assigns[:subtitle].present? %>
          <p class="erp-drawer__subtitle"><%= local_assigns[:subtitle] %></p>
        <% end %>
      </div>
      <button class="icon-button" type="button" aria-label="<%= t("common.actions.close") %>" data-action="modal#close">
        <i class="bi bi-x-lg" aria-hidden="true"></i>
      </button>
    </div>
    <div class="erp-drawer__body">
      <%= yield %>
    </div>
  </section>
</div>
```

- [ ] **Step 2: Implement the inventory index shell**

Replace `app/views/reports/inventory.html.erb` with a structure like:

```erb
<h1 class="page-title"><%= t("reports.inventory.title") %></h1>

<div class="report-stack inventory-page">
  <section class="panel">
    <%= form_with url: "/reports/inventory", method: :get, local: true, html: { class: "report-form" } do |form| %>
      <div class="field">
        <%= form.label :sku, t("reports.inventory.filters.sku") %>
        <%= form.search_field :sku, value: @sku_query, placeholder: t("reports.inventory.filters.sku_placeholder") %>
      </div>
      <%= form.button t("reports.inventory.filters.submit"), class: "button", type: "submit" %>
      <% if @sku_query.present? %>
        <%= link_to t("reports.inventory.filters.reset"), "/reports/inventory", class: "button button-secondary" %>
      <% end %>
    <% end %>
  </section>

  <section class="panel">
    <h2 class="section-title"><%= t("reports.inventory.sections.inventory_list") %></h2>
    <div class="table-scroll">
      <table class="inventory-list-table inventory-list-table--redesigned">
        <thead>
          <tr>
            <th><%= t("reports.inventory.fields.sku") %></th>
            <th><%= t("reports.inventory.fields.incoming_quantity") %></th>
            <th><%= t("reports.inventory.fields.book_stock") %></th>
            <th><%= t("reports.inventory.fields.platform_stock") %></th>
            <th><%= t("reports.inventory.fields.available_stock") %></th>
            <th><%= t("reports.inventory.fields.cache_updated_at") %></th>
            <th><%= t("reports.inventory.fields.actions") %></th>
          </tr>
        </thead>
        <tbody>
          <% @inventory_rows.each do |row| %>
            <tr>
              <td>
                <div class="inventory-row-main">
                  <strong><%= row[:sku_code] %></strong>
                  <span><%= row[:product_name] %></span>
                </div>
              </td>
              <td class="numeric"><%= row[:incoming_quantity] %></td>
              <td class="numeric"><%= row[:book_stock] %></td>
              <td class="numeric"><%= row[:platform_stock] %></td>
              <td class="numeric"><%= row[:available_stock] %></td>
              <td><%= display_time(row[:cache_updated_at]) %></td>
              <td>
                <%= link_to t("reports.inventory.actions.view_detail"),
                            report_inventory_detail_path(row[:sku_code], request.query_parameters.slice(:locale, :sku).merge(detail_tab: "incoming")),
                            class: "button button-secondary",
                            data: { turbo_frame: "inventory_drawer" } %>
              </td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
  </section>

  <%= turbo_frame_tag "inventory_drawer" %>
</div>
```

- [ ] **Step 3: Implement the drawer template and section partials**

Create `app/views/reports/inventory_detail.html.erb`:

```erb
<%= turbo_frame_tag "inventory_drawer" do %>
  <%= render "inventory_drawer", detail: @inventory_detail %>
<% end %>
```

Create `app/views/reports/_inventory_drawer.html.erb`:

```erb
<%= render "shared/overlay_drawer",
           title_id: "inventory-drawer-title",
           eyebrow: t("reports.inventory.drawer.eyebrow"),
           title: detail[:sku_code],
           subtitle: detail[:product_name] do %>
  <%= render "inventory_summary_cards", detail: detail %>

  <nav class="sku-detail-tabs inventory-drawer-tabs">
    <% [["incoming", t("reports.inventory.drawer.tabs.incoming")],
        ["book", t("reports.inventory.drawer.tabs.book")],
        ["platform", t("reports.inventory.drawer.tabs.platform")]].each do |key, label| %>
      <%= link_to label,
                  report_inventory_detail_path(detail[:sku_code], detail_tab: key, book_batch_page: 1, locale: params[:locale].presence),
                  data: { turbo_frame: "inventory_drawer" },
                  aria: (detail[:active_detail_tab] == key ? { current: "page" } : nil) %>
    <% end %>
  </nav>

  <% case detail[:active_detail_tab] %>
  <% when "incoming" %>
    <%= render "inventory_incoming_batches", detail: detail %>
  <% when "book" %>
    <%= render "inventory_book_inventory", detail: detail %>
  <% else %>
    <%= render "inventory_platform_breakdown", detail: detail %>
  <% end %>
<% end %>
```

- [ ] **Step 4: Add minimal content partials**

Create partials with straightforward server-rendered tables:

`app/views/reports/_inventory_summary_cards.html.erb`

```erb
<section class="inventory-drawer-section">
  <div class="summary-grid">
    <div class="weekly-profit-summary-card">
      <div class="summary-label"><%= t("reports.inventory.fields.incoming_quantity") %></div>
      <div class="summary-value"><%= detail[:incoming_quantity] %></div>
    </div>
    <div class="weekly-profit-summary-card">
      <div class="summary-label"><%= t("reports.inventory.fields.book_stock") %></div>
      <div class="summary-value"><%= detail[:summary][:book_stock] %></div>
    </div>
    <div class="weekly-profit-summary-card">
      <div class="summary-label"><%= t("reports.inventory.fields.platform_stock") %></div>
      <div class="summary-value"><%= detail[:summary][:platform_stock] %></div>
    </div>
    <div class="weekly-profit-summary-card">
      <div class="summary-label"><%= t("reports.inventory.fields.available_stock") %></div>
      <div class="summary-value"><%= detail[:summary][:available_stock] %></div>
    </div>
  </div>
</section>
```

`app/views/reports/_inventory_incoming_batches.html.erb`

```erb
<section class="panel inventory-drawer-section">
  <h3 class="section-title"><%= t("reports.inventory.drawer.sections.incoming_batches") %></h3>
  <div class="table-scroll">
    <table>
      <thead>
        <tr>
          <th><%= t("reports.inventory.drawer.fields.batch_code") %></th>
          <th><%= t("reports.inventory.drawer.fields.status") %></th>
          <th><%= t("reports.inventory.drawer.fields.expected_arrival_on") %></th>
          <th><%= t("reports.inventory.drawer.fields.quantity") %></th>
        </tr>
      </thead>
      <tbody>
        <% if detail[:incoming_batches].any? %>
          <% detail[:incoming_batches].each do |batch| %>
            <tr>
              <td><%= batch[:batch_code] %></td>
              <td><%= batch[:status] %></td>
              <td><%= batch[:expected_arrival_on] || "-" %></td>
              <td><%= batch[:purchased_quantity] %></td>
            </tr>
          <% end %>
        <% else %>
          <tr><td colspan="4" class="empty-state"><%= t("reports.inventory.drawer.empty.incoming_batches") %></td></tr>
        <% end %>
      </tbody>
    </table>
  </div>
</section>
```

`app/views/reports/_inventory_book_inventory.html.erb`

```erb
<section class="panel inventory-drawer-section">
  <h3 class="section-title"><%= t("reports.inventory.drawer.sections.book_batches") %></h3>
  <div class="table-scroll">
    <table>
      <thead>
        <tr>
          <th><%= t("reports.inventory.drawer.fields.batch_code") %></th>
          <th><%= t("reports.inventory.drawer.fields.batch_type") %></th>
          <th><%= t("reports.inventory.drawer.fields.note") %></th>
          <th><%= t("reports.inventory.drawer.fields.quantity") %></th>
          <th><%= t("reports.inventory.drawer.fields.received_on") %></th>
        </tr>
      </thead>
      <tbody>
        <% if detail[:book_batches].any? %>
          <% detail[:book_batches].each do |batch| %>
            <tr>
              <td><%= batch[:batch_code] %></td>
              <td><%= batch[:batch_type] %></td>
              <td><%= batch[:defect_offset_note].presence || "-" %></td>
              <td><%= batch[:received_quantity] %></td>
              <td><%= batch[:received_on] || "-" %></td>
            </tr>
          <% end %>
        <% else %>
          <tr><td colspan="5" class="empty-state"><%= t("reports.inventory.drawer.empty.book_batches") %></td></tr>
        <% end %>
      </tbody>
    </table>
  </div>
</section>
```

`app/views/reports/_inventory_platform_breakdown.html.erb`

```erb
<section class="panel inventory-drawer-section">
  <h3 class="section-title"><%= t("reports.inventory.drawer.sections.platform_breakdown") %></h3>
  <div class="table-scroll">
    <table>
      <thead>
        <tr>
          <th><%= t("reports.sku_detail.fields.platform") %></th>
          <th><%= t("reports.sku_detail.fields.store") %></th>
          <th><%= t("reports.sku_detail.fields.fulfillment_mode") %></th>
          <th><%= t("reports.inventory.drawer.fields.quantity") %></th>
          <th><%= t("reports.sku_detail.inventory.latest_synced_at") %></th>
        </tr>
      </thead>
      <tbody>
        <% if detail[:platform_breakdown].any? %>
          <% detail[:platform_breakdown].each do |row| %>
            <tr>
              <td><%= platform_label_for_sales(row[:platform]) %></td>
              <td><%= row[:store_name] %></td>
              <td><%= row[:fulfillment_type].to_s.upcase %></td>
              <td><%= row[:quantity] %></td>
              <td><%= display_time(row[:latest_synced_at]) %></td>
            </tr>
          <% end %>
        <% else %>
          <tr><td colspan="5" class="empty-state"><%= t("reports.inventory.drawer.empty.platform_breakdown") %></td></tr>
        <% end %>
      </tbody>
    </table>
  </div>
</section>
```

- [ ] **Step 5: Run the controller tests again**

Run:

```bash
SKIP_JS_BUILD=1 bundle exec ruby bin/rails test test/controllers/reports_controller_test.rb -n "/redesigned inventory workspace|inventory detail renders turbo drawer content/"
```

Expected: PASS or fail only on copy/I18n mismatches.

- [ ] **Step 6: Commit the ERB drawer implementation**

```bash
git add app/views/shared/_overlay_drawer.html.erb app/views/reports/inventory.html.erb app/views/reports/inventory_detail.html.erb app/views/reports/_inventory_drawer.html.erb app/views/reports/_inventory_summary_cards.html.erb app/views/reports/_inventory_incoming_batches.html.erb app/views/reports/_inventory_book_inventory.html.erb app/views/reports/_inventory_platform_breakdown.html.erb
git commit -m "feat: build turbo drawer inventory page"
```

### Task 5: Add Drawer Styling And Any Minimal Stimulus Support

**Files:**
- Modify: `app/assets/stylesheets/application.css`
- Modify: `app/javascript/controllers/modal_controller.js` only if needed
- Modify: `app/javascript/application.js` only if a new controller is introduced

- [ ] **Step 1: Add the failing style assertions only if necessary**

If tests do not already prove the structure enough, skip style assertions and keep verification visual/manual.

- [ ] **Step 2: Extend CSS with reusable drawer blocks**

Add scoped classes to `app/assets/stylesheets/application.css` near the existing modal styles:

```css
.erp-drawer-backdrop {
  position: fixed;
  inset: 0;
  z-index: 1002;
  display: flex;
  justify-content: flex-end;
  background: rgba(24, 34, 53, 0.42);
}

.erp-drawer {
  width: min(920px, calc(100vw - 24px));
  height: 100vh;
  overflow: auto;
  border-left: 1px solid var(--erp-border);
  background: var(--erp-surface);
  box-shadow: -24px 0 64px rgba(24, 34, 53, 0.24);
  padding: 22px 22px 28px;
}

.erp-drawer__header {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 16px;
  margin-bottom: 18px;
  padding-bottom: 14px;
  border-bottom: 1px solid var(--erp-border);
}

.erp-drawer__eyebrow {
  margin: 0 0 6px;
  color: var(--erp-muted);
  font-size: 12px;
  font-weight: 700;
}

.erp-drawer__header h2 {
  margin: 0;
  font-size: 22px;
}

.erp-drawer__subtitle {
  margin: 6px 0 0;
  color: var(--erp-muted);
}

.erp-drawer__body {
  display: grid;
  gap: 16px;
}

.inventory-page .inventory-list-table--redesigned {
  min-width: 980px;
}

.inventory-row-main {
  display: grid;
  gap: 4px;
}

.inventory-row-main strong {
  font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
}

.inventory-drawer-tabs {
  margin-top: 0;
}

.inventory-drawer-section {
  display: grid;
  gap: 12px;
}

@media (max-width: 900px) {
  .erp-drawer {
    width: 100vw;
    max-width: 100vw;
    padding: 18px 16px 22px;
  }
}
```

- [ ] **Step 3: Reuse the existing modal controller if possible**

Keep `app/javascript/controllers/modal_controller.js` unchanged if `close` and backdrop click already work for the new drawer DOM.

If a rename or extraction becomes necessary, do the minimum:

```javascript
import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  close() {
    this.element.closest("turbo-frame").innerHTML = "";
  }

  closeOnBackdrop(event) {
    if (event.target === this.element) this.close();
  }
}
```

- [ ] **Step 4: Run the controller tests to confirm no structural regressions**

Run:

```bash
SKIP_JS_BUILD=1 bundle exec ruby bin/rails test test/controllers/reports_controller_test.rb -n "/inventory/"
```

Expected: PASS for the inventory-focused tests adjusted to the new UI contract.

- [ ] **Step 5: Commit the styling layer**

```bash
git add app/assets/stylesheets/application.css app/javascript/controllers/modal_controller.js app/javascript/application.js
git commit -m "style: add reusable turbo drawer styling"
```

### Task 6: Add I18n Entries And Align Copy

**Files:**
- Modify: `config/locales/zh.yml`
- Modify: `config/locales/en.yml`
- Modify: `config/locales/ru.yml`
- Test: `test/controllers/reports_controller_test.rb`

- [ ] **Step 1: Add missing translation keys**

Add keys under `reports.inventory` for:

- list fields:
  - `incoming_quantity`
  - `book_stock`
  - `platform_stock`
  - `available_stock`
  - `view_detail`

- drawer:
  - `eyebrow`
  - `tabs.incoming`
  - `tabs.book`
  - `tabs.platform`
  - section titles
  - batch/platform field labels
  - empty states

- [ ] **Step 2: Update any tests that assert old copy**

Adjust old assertions that still expect:

- `采购`
- `WB_FBW`
- `Ozon_FBO`
- `白俄可用`

to the new inventory workspace copy.

- [ ] **Step 3: Run the targeted controller tests**

Run:

```bash
SKIP_JS_BUILD=1 bundle exec ruby bin/rails test test/controllers/reports_controller_test.rb -n "/inventory/"
```

Expected: PASS

- [ ] **Step 4: Commit the translation alignment**

```bash
git add config/locales/zh.yml config/locales/en.yml config/locales/ru.yml test/controllers/reports_controller_test.rb
git commit -m "i18n: localize redesigned inventory page"
```

### Task 7: Run Full Verification For The Inventory Redesign

**Files:**
- Modify: none
- Test: `test/controllers/reports_controller_test.rb`
- Test: `test/services/ec/sku_inventory_overview_test.rb`
- Test: `test/services/ec/inventory_page_row_query_test.rb`
- Test: `test/services/ec/inventory_page_detail_query_test.rb`

- [ ] **Step 1: Run focused service and controller verification**

Run:

```bash
SKIP_JS_BUILD=1 bundle exec ruby bin/rails test \
  test/services/ec/sku_inventory_overview_test.rb \
  test/services/ec/inventory_page_row_query_test.rb \
  test/services/ec/inventory_page_detail_query_test.rb \
  test/controllers/reports_controller_test.rb
```

Expected: PASS

- [ ] **Step 2: Review rendered behavior manually in code**

Check these files for consistency before closing:

- `app/controllers/reports_controller.rb`
- `app/views/reports/inventory.html.erb`
- `app/views/reports/_inventory_drawer.html.erb`
- `app/services/ec/inventory_page_detail_query.rb`

Verify:

- no hard-coded user-facing strings outside I18n
- `Ec::SkuInventoryOverview` was not turned into a page assembler
- `incoming_batches`, `book_batches`, and `platform_breakdown` all come from the agreed direct sources

- [ ] **Step 3: Commit the final verified state**

```bash
git add app/controllers/reports_controller.rb app/views/reports app/views/shared/_overlay_drawer.html.erb app/services/ec/inventory_page_row_query.rb app/services/ec/inventory_page_detail_query.rb app/assets/stylesheets/application.css config/routes.rb config/locales/zh.yml config/locales/en.yml config/locales/ru.yml test/controllers/reports_controller_test.rb test/services/ec/inventory_page_row_query_test.rb test/services/ec/inventory_page_detail_query_test.rb
git commit -m "feat: redesign inventory page with turbo drawer"
```
