# Store Product Operators Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add multi-user operator assignments to store platform products and manage them from the ERP store detail page.

**Architecture:** Store products are existing `Ec::SkuProduct` rows, so operator ownership belongs to a new join model between `Ec::SkuProduct` and `User`. `Erp::StoresController#show` becomes the store detail page and a small nested controller updates one product's operator collection at a time. Existing ERP permissions stay in place: `view_erp` can view, `manage_skus` can update.

**Tech Stack:** Rails 8, ActiveRecord, ERB, Rails I18n, Minitest integration tests.

---

## File Map

- Create `db/migrate/20260629000001_create_ec_sku_product_operators.rb`: join table, foreign keys, unique index.
- Create `app/models/ec/sku_product_operator.rb`: join model validations and associations.
- Modify `app/models/ec/sku_product.rb`: add operator associations.
- Modify `app/models/user.rb`: add reverse operator associations.
- Modify `config/routes.rb`: enable `erp/stores#show` and add nested operator update route.
- Modify `app/controllers/erp/stores_controller.rb`: add `show`, load product rows, load operator candidates, expose existing helper methods.
- Create `app/controllers/erp/store_sku_product_operators_controller.rb`: replace operators for one store product.
- Modify `app/views/erp/stores/index.html.erb`: link store rows to the new detail page.
- Create `app/views/erp/stores/show.html.erb`: store summary and product/operator management table.
- Modify `config/locales/zh.yml`, `config/locales/en.yml`, `config/locales/ru.yml`: add all visible text.
- Modify `test/controllers/erp/stores_controller_test.rb`: add regression coverage.

## Task 1: Data Model

**Files:**
- Create: `db/migrate/20260629000001_create_ec_sku_product_operators.rb`
- Create: `app/models/ec/sku_product_operator.rb`
- Modify: `app/models/ec/sku_product.rb`
- Modify: `app/models/user.rb`
- Test: `test/controllers/erp/stores_controller_test.rb`

- [ ] **Step 1: Write the failing model-backed test**

Add this test method before the `private` section in `test/controllers/erp/stores_controller_test.rb`:

```ruby
  test "sku product can have multiple operator users" do
    sku = Ec::Sku.create!(
      sku_code: "STORE-OPS-#{token_suffix}",
      product_name: "店铺运营 SKU #{token_suffix}",
      is_active: true
    )
    product = Ec::SkuProduct.create!(
      sku_code: sku.sku_code,
      store: @store,
      product_id: "P-#{token_suffix}",
      offer_id: "OFFER-#{token_suffix}",
      product_name: "店铺运营商品 #{token_suffix}"
    )
    operator_a = create_user_with_roles("store-operator-a-#{@token.downcase}@example.com", "operator")
    operator_b = create_user_with_roles("store-operator-b-#{@token.downcase}@example.com", "operator")

    product.operators = [operator_a, operator_b]
    product.save!

    assert_equal [operator_a.email, operator_b.email].sort, product.reload.operators.map(&:email).sort
    assert_includes operator_a.reload.operated_sku_products, product
  ensure
    Ec::SkuProduct.where(sku_code: sku&.sku_code).delete_all
    Ec::Sku.with_deleted.where(id: sku&.id).delete_all if sku
    UserRole.joins(:user).where("users.email LIKE ?", "store-operator-%#{@token.downcase}%").delete_all
    User.where("email LIKE ?", "store-operator-%#{@token.downcase}%").delete_all
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
rbenv exec ruby bin/rails test test/controllers/erp/stores_controller_test.rb -n "test_sku_product_can_have_multiple_operator_users"
```

Expected: FAIL or ERROR because `Ec::SkuProduct#operators` is not defined and the join table does not exist.

- [ ] **Step 3: Add migration**

Create `db/migrate/20260629000001_create_ec_sku_product_operators.rb`:

```ruby
class CreateEcSkuProductOperators < ActiveRecord::Migration[8.0]
  def change
    create_table :ec_sku_product_operators do |t|
      t.references :sku_product, null: false, foreign_key: { to_table: :ec_sku_products }
      t.references :user, null: false, foreign_key: true
      t.timestamps
    end

    add_index :ec_sku_product_operators,
      [:sku_product_id, :user_id],
      unique: true,
      name: "idx_ec_sku_product_operators_unique"
  end
end
```

- [ ] **Step 4: Add join model**

Create `app/models/ec/sku_product_operator.rb`:

```ruby
module Ec
  class SkuProductOperator < ApplicationRecord
    self.table_name = "ec_sku_product_operators"

    belongs_to :sku_product, class_name: "Ec::SkuProduct"
    belongs_to :user

    validates :sku_product, :user, presence: true
    validates :user_id, uniqueness: { scope: :sku_product_id }
  end
end
```

- [ ] **Step 5: Add associations**

In `app/models/ec/sku_product.rb`, add after the existing `belongs_to` lines:

```ruby
    has_many :operator_assignments,
      class_name: "Ec::SkuProductOperator",
      foreign_key: :sku_product_id,
      dependent: :destroy
    has_many :operators, through: :operator_assignments, source: :user
```

In `app/models/user.rb`, add after the existing `has_many :feedback_tasks` line:

```ruby
  has_many :sku_product_operator_assignments,
    class_name: "Ec::SkuProductOperator",
    dependent: :destroy
  has_many :operated_sku_products,
    through: :sku_product_operator_assignments,
    source: :sku_product
```

- [ ] **Step 6: Migrate test database**

Run:

```bash
rbenv exec ruby bin/rails db:migrate RAILS_ENV=test
```

Expected: exit 0 and migration creates `ec_sku_product_operators`.

- [ ] **Step 7: Run test to verify it passes**

Run:

```bash
rbenv exec ruby bin/rails test test/controllers/erp/stores_controller_test.rb -n "test_sku_product_can_have_multiple_operator_users"
```

Expected: PASS.

## Task 2: Store Detail Page

**Files:**
- Modify: `config/routes.rb`
- Modify: `app/controllers/erp/stores_controller.rb`
- Modify: `app/views/erp/stores/index.html.erb`
- Create: `app/views/erp/stores/show.html.erb`
- Modify: `config/locales/zh.yml`
- Modify: `config/locales/en.yml`
- Modify: `config/locales/ru.yml`
- Test: `test/controllers/erp/stores_controller_test.rb`

- [ ] **Step 1: Write failing detail-page tests**

Add these tests before the `private` section in `test/controllers/erp/stores_controller_test.rb`:

```ruby
  test "show renders store products and current operators for manager" do
    sku = Ec::Sku.create!(
      sku_code: "STORE-SHOW-#{token_suffix}",
      product_name: "店铺详情 SKU #{token_suffix}",
      is_active: true
    )
    product = Ec::SkuProduct.create!(
      sku_code: sku.sku_code,
      store: @store,
      product_id: "SHOW-#{token_suffix}",
      offer_id: "SHOW-OFFER-#{token_suffix}",
      product_name: "店铺详情商品 #{token_suffix}"
    )
    operator = create_user_with_roles("store-show-operator-#{@token.downcase}@example.com", "operator")
    product.operators = [operator]

    get "/erp/stores/#{@store.id}", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", @store.store_name
    assert_select "dt", "店铺 ID"
    assert_select "dd", "SHOP-%03d" % @store.id
    assert_select "h2", "店铺商品"
    assert_select "td", sku.sku_code
    assert_select "td", "SHOW-#{token_suffix}"
    assert_select "td", "SHOW-OFFER-#{token_suffix}"
    assert_select "td", "店铺详情商品 #{token_suffix}"
    assert_select ".operator-list", operator.email
    assert_select "form[action=?][method=?]", "/erp/stores/#{@store.id}/sku_products/#{product.id}/operators", "post"
    assert_select "input[type=?][name=?][value=?]", "checkbox", "operator_ids[]", operator.id.to_s
  ensure
    Ec::SkuProduct.where(sku_code: sku&.sku_code).delete_all
    Ec::Sku.with_deleted.where(id: sku&.id).delete_all if sku
    UserRole.joins(:user).where("users.email LIKE ?", "store-show-operator-#{@token.downcase}%").delete_all
    User.where("email LIKE ?", "store-show-operator-#{@token.downcase}%").delete_all
  end

  test "show hides operator management form for read only erp user" do
    readonly_user = create_user_with_roles("store-readonly-#{@token.downcase}@example.com", "operator")
    sign_in readonly_user
    sku = Ec::Sku.create!(
      sku_code: "STORE-READ-#{token_suffix}",
      product_name: "只读店铺 SKU #{token_suffix}",
      is_active: true
    )
    product = Ec::SkuProduct.create!(
      sku_code: sku.sku_code,
      store: @store,
      product_id: "READ-#{token_suffix}",
      product_name: "只读店铺商品 #{token_suffix}"
    )

    get "/erp/stores/#{@store.id}", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "td", "READ-#{token_suffix}"
    assert_select "form[action=?]", "/erp/stores/#{@store.id}/sku_products/#{product.id}/operators", count: 0
  ensure
    sign_in @current_user
    Ec::SkuProduct.where(sku_code: sku&.sku_code).delete_all
    Ec::Sku.with_deleted.where(id: sku&.id).delete_all if sku
    UserRole.joins(:user).where("users.email LIKE ?", "store-readonly-#{@token.downcase}%").delete_all
    User.where("email LIKE ?", "store-readonly-#{@token.downcase}%").delete_all
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
rbenv exec ruby bin/rails test test/controllers/erp/stores_controller_test.rb -n "/show renders|show hides/"
```

Expected: FAIL because `/erp/stores/:id` is not routed.

- [ ] **Step 3: Add routes**

In `config/routes.rb`, replace:

```ruby
    resources :stores, except: [:show, :destroy]
```

with:

```ruby
    resources :stores, except: [:destroy] do
      patch "sku_products/:id/operators" => "store_sku_product_operators#update", as: :sku_product_operators
    end
```

- [ ] **Step 4: Add store detail loading**

In `app/controllers/erp/stores_controller.rb`, change the `before_action` line to:

```ruby
    before_action :set_store, only: [:show, :edit, :update]
```

Add this action after `index`:

```ruby
    def show
      @sku_products = @store.sku_products.includes(:sku, :operators).ordered
      @operator_candidates = operator_candidates
    end
```

Add this private method before `store_params`:

```ruby
    def operator_candidates
      User
        .where(active: true)
        .left_joins(:roles)
        .select("users.*, MAX(CASE WHEN roles.code = 'operator' THEN 0 ELSE 1 END) AS operator_sort")
        .group("users.id")
        .order("operator_sort ASC, users.email ASC")
    end
```

- [ ] **Step 5: Link store list to detail page**

In `app/views/erp/stores/index.html.erb`, replace the store name cell:

```erb
            <td><span class="zh-name"><%= store.store_name %></span></td>
```

with:

```erb
            <td><%= link_to store.store_name, erp_store_path(store, current_locale_params), class: "zh-name" %></td>
```

Inside the `.row-actions` div, before the existing edit link, add:

```erb
                <%= link_to erp_store_path(store, current_locale_params), class: "btn btn-ghost btn-sm" do %>
                  <i class="bi bi-eye" aria-hidden="true"></i>
                  <%= t("erp.common.actions.view") %>
                <% end %>
```

- [ ] **Step 6: Add store detail view**

Create `app/views/erp/stores/show.html.erb`:

```erb
<% content_for :page_heading, @store.store_name %>

<div class="resource-header">
  <div>
    <p class="resource-eyebrow"><%= t("erp.stores.show.eyebrow") %></p>
    <h1 class="page-title"><%= @store.store_name %></h1>
  </div>
  <div class="resource-actions">
    <%= link_to t("erp.common.actions.back"), erp_stores_path(current_locale_params), class: "button button-secondary" %>
    <% if can?(:manage_skus) %>
      <%= link_to t("erp.common.actions.edit"), erp_edit_store_path(@store, current_locale_params), class: "button" %>
    <% end %>
  </div>
</div>

<div class="report-stack">
  <section class="panel">
    <h2 class="section-title"><%= t("erp.stores.show.summary") %></h2>
    <dl class="definition-list">
      <dt><%= t("erp.stores.fields.store_id") %></dt>
      <dd><%= store_public_id(@store) %></dd>
      <dt><%= t("erp.common.platform") %></dt>
      <dd><%= store_platform_label(@store.platform) %></dd>
      <dt><%= t("erp.common.name") %></dt>
      <dd><%= @store.store_name %></dd>
      <dt><%= t("erp.stores.fields.company_scale") %></dt>
      <dd><%= store_company_type_label(@store.company_type) %></dd>
      <dt><%= t("erp.stores.fields.registration_country") %></dt>
      <dd><%= store_country_label(@store.registration_country) %></dd>
      <dt><%= t("erp.stores.fields.is_active") %></dt>
      <dd><%= @store.is_active ? t("erp.common.statuses.active") : t("erp.common.statuses.inactive") %></dd>
      <dt><%= t("erp.common.memo") %></dt>
      <dd><%= erp_value(@store.memo) %></dd>
    </dl>
  </section>

  <section class="panel">
    <h2 class="section-title"><%= t("erp.stores.show.products") %></h2>
    <div class="table-scroll">
      <table class="raw-product-options">
        <thead>
          <tr>
            <th><%= t("erp.skus.fields.sku_code") %></th>
            <th><%= t("erp.sku_products.fields.product_id") %></th>
            <th><%= t("erp.sku_products.fields.offer_id") %></th>
            <th><%= t("erp.sku_products.fields.product_name") %></th>
            <th><%= t("erp.stores.fields.operators") %></th>
            <th><%= t("erp.sku_products.fields.product_attributes_link") %></th>
            <th><%= t("erp.sku_products.fields.store_link") %></th>
            <% if can?(:manage_skus) %>
              <th><%= t("erp.common.actions.actions") %></th>
            <% end %>
          </tr>
        </thead>
        <tbody>
          <% if @sku_products.any? %>
            <% @sku_products.each do |product| %>
              <tr>
                <td><%= product.sku_code %></td>
                <td><%= product.product_id %></td>
                <td><%= erp_value(product.offer_id) %></td>
                <td><span data-controller="long-text" data-long-text-limit-value="50"><%= erp_value(product.product_name) %></span></td>
                <td>
                  <span class="operator-list"><%= product.operators.map(&:email).join(", ").presence || t("erp.stores.empty.no_operators") %></span>
                </td>
                <td><%= link_to t("erp.sku_products.actions.view_attributes"), erp_platform_product_path(product.platform, product.store_id, product.product_id) %></td>
                <td>
                  <% edit_url = product_edit_url(product.platform, product.platform_sku_id.presence || product.product_id) %>
                  <% if edit_url %>
                    <%= link_to t("erp.sku_products.actions.open_platform_product"), edit_url, target: "_blank", rel: "noreferrer noopener" %>
                  <% else %>
                    -
                  <% end %>
                </td>
                <% if can?(:manage_skus) %>
                  <td>
                    <%= form_with url: erp_store_sku_product_operators_path(@store, product), method: :patch, local: true, class: "operator-assignment-form" do %>
                      <div class="operator-checkboxes">
                        <% @operator_candidates.each do |user| %>
                          <label>
                            <%= check_box_tag "operator_ids[]", user.id, product.operator_ids.include?(user.id) %>
                            <%= user.email %>
                          </label>
                        <% end %>
                      </div>
                      <button class="button button-secondary" type="submit"><%= t("erp.stores.actions.save_operators") %></button>
                    <% end %>
                  </td>
                <% end %>
              </tr>
            <% end %>
          <% else %>
            <tr>
              <td colspan="<%= can?(:manage_skus) ? 8 : 7 %>" class="empty-state"><%= t("erp.stores.empty.no_products") %></td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
  </section>
</div>
```

- [ ] **Step 7: Add I18n text**

In each locale file, add missing keys. For `config/locales/zh.yml`, under `erp.common.actions`, add:

```yaml
        back: "返回"
        view: "查看"
```

Under `erp.stores.actions`, add:

```yaml
        save_operators: "保存运营人员"
```

Under `erp.stores.empty`, add:

```yaml
        no_operators: "未绑定"
        no_products: "这个店铺还没有绑定平台商品。"
```

Under `erp.stores.fields`, add:

```yaml
        operators: "运营人员"
```

Under `erp.stores`, add:

```yaml
      show:
        eyebrow: "店铺详情"
        products: "店铺商品"
        summary: "店铺信息"
```

For `config/locales/en.yml`, use:

```yaml
        back: "Back"
        view: "View"
        save_operators: "Save operators"
        no_operators: "Unassigned"
        no_products: "This store has no platform product bindings yet."
        operators: "Operators"
      show:
        eyebrow: "Store detail"
        products: "Store products"
        summary: "Store information"
```

For `config/locales/ru.yml`, use:

```yaml
        back: "Назад"
        view: "Просмотр"
        save_operators: "Сохранить операторов"
        no_operators: "Не назначено"
        no_products: "У этого магазина пока нет связей с товарами платформ."
        operators: "Операторы"
      show:
        eyebrow: "Детали магазина"
        products: "Товары магазина"
        summary: "Информация о магазине"
```

- [ ] **Step 8: Run tests to verify page passes**

Run:

```bash
rbenv exec ruby bin/rails test test/controllers/erp/stores_controller_test.rb -n "/show renders|show hides/"
```

Expected: PASS.

## Task 3: Operator Update Endpoint

**Files:**
- Create: `app/controllers/erp/store_sku_product_operators_controller.rb`
- Test: `test/controllers/erp/stores_controller_test.rb`

- [ ] **Step 1: Write failing update tests**

Add these tests before the `private` section in `test/controllers/erp/stores_controller_test.rb`:

```ruby
  test "update operators replaces assigned user set" do
    sku = Ec::Sku.create!(
      sku_code: "STORE-UPD-#{token_suffix}",
      product_name: "更新运营 SKU #{token_suffix}",
      is_active: true
    )
    product = Ec::SkuProduct.create!(
      sku_code: sku.sku_code,
      store: @store,
      product_id: "UPD-#{token_suffix}",
      product_name: "更新运营商品 #{token_suffix}"
    )
    old_operator = create_user_with_roles("store-old-operator-#{@token.downcase}@example.com", "operator")
    new_operator = create_user_with_roles("store-new-operator-#{@token.downcase}@example.com", "operator")
    inactive_operator = create_user_with_roles("store-inactive-operator-#{@token.downcase}@example.com", "operator")
    inactive_operator.update!(active: false)
    product.operators = [old_operator]

    patch "/erp/stores/#{@store.id}/sku_products/#{product.id}/operators", params: {
      operator_ids: [new_operator.id.to_s, inactive_operator.id.to_s]
    }

    assert_redirected_to "/erp/stores/#{@store.id}"
    assert_equal [new_operator.id], product.reload.operator_ids
  ensure
    Ec::SkuProduct.where(sku_code: sku&.sku_code).delete_all
    Ec::Sku.with_deleted.where(id: sku&.id).delete_all if sku
    UserRole.joins(:user).where("users.email LIKE ?", "store-%operator-#{@token.downcase}%").delete_all
    User.where("email LIKE ?", "store-%operator-#{@token.downcase}%").delete_all
  end

  test "update operators only updates products under the current store" do
    other_store = Ec::Store.create!(
      platform: "ozon",
      store_name: "其他 Ozon 店 #{token_suffix}",
      company_type: "general",
      registration_country: "belarus",
      is_active: true
    )
    sku = Ec::Sku.create!(
      sku_code: "STORE-WRONG-#{token_suffix}",
      product_name: "错误店铺 SKU #{token_suffix}",
      is_active: true
    )
    product = Ec::SkuProduct.create!(
      sku_code: sku.sku_code,
      store: other_store,
      product_id: "WRONG-#{token_suffix}",
      product_name: "错误店铺商品 #{token_suffix}"
    )
    operator = create_user_with_roles("store-wrong-operator-#{@token.downcase}@example.com", "operator")

    patch "/erp/stores/#{@store.id}/sku_products/#{product.id}/operators", params: {
      operator_ids: [operator.id.to_s]
    }

    assert_response :not_found
    assert_empty product.reload.operators
  ensure
    Ec::SkuProduct.where(sku_code: sku&.sku_code).delete_all
    Ec::Sku.with_deleted.where(id: sku&.id).delete_all if sku
    other_store&.destroy
    UserRole.joins(:user).where("users.email LIKE ?", "store-wrong-operator-#{@token.downcase}%").delete_all
    User.where("email LIKE ?", "store-wrong-operator-#{@token.downcase}%").delete_all
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
rbenv exec ruby bin/rails test test/controllers/erp/stores_controller_test.rb -n "/update operators/"
```

Expected: FAIL because `Erp::StoreSkuProductOperatorsController` does not exist.

- [ ] **Step 3: Add update controller**

Create `app/controllers/erp/store_sku_product_operators_controller.rb`:

```ruby
module Erp
  class StoreSkuProductOperatorsController < BaseController
    before_action -> { require_permission!(:manage_skus) }
    before_action :set_store
    before_action :set_sku_product

    def update
      @sku_product.operators = operator_candidates.where(id: operator_ids)
      redirect_to erp_store_path(@store)
    end

    private

    def set_store
      @store = Ec::Store.find(params[:store_id])
    end

    def set_sku_product
      @sku_product = @store.sku_products.find_by(id: params[:id])
      render plain: "Not Found", status: :not_found unless @sku_product
    end

    def operator_ids
      Array(params[:operator_ids]).reject(&:blank?)
    end

    def operator_candidates
      User.where(active: true)
    end
  end
end
```

- [ ] **Step 4: Run update tests to verify they pass**

Run:

```bash
rbenv exec ruby bin/rails test test/controllers/erp/stores_controller_test.rb -n "/update operators/"
```

Expected: PASS.

## Task 4: Full Verification and Cleanup

**Files:**
- Review all files touched in Tasks 1-3.

- [ ] **Step 1: Run the complete store controller test**

Run:

```bash
rbenv exec ruby bin/rails test test/controllers/erp/stores_controller_test.rb
```

Expected: all tests pass.

- [ ] **Step 2: Run schema check**

Run:

```bash
git diff -- db/schema.rb db/migrate/20260629000001_create_ec_sku_product_operators.rb
```

Expected: diff shows the new join table in schema and the migration file.

- [ ] **Step 3: Review application diff**

Run:

```bash
git diff -- app/models app/controllers app/views config/routes.rb config/locales test/controllers/erp/stores_controller_test.rb
```

Expected: only changes required for store product operator assignment.

- [ ] **Step 4: Final test command**

Run:

```bash
rbenv exec ruby bin/rails test test/controllers/erp/stores_controller_test.rb
```

Expected: all tests pass immediately before reporting completion.
