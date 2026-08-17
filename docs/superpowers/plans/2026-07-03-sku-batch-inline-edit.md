# SKU Batch Inline Edit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add immediate-save inline editing for the editable batch columns already shown in `/erp/skus`, with reusable Turbo/Stimulus infrastructure and minimal Rails test coverage.

**Architecture:** The feature keeps rendering and validation on the server by using per-cell Turbo frames and Turbo Stream responses from `Erp::SkuBatchesController#update`. Reuse comes from a shared inline-cell partial, a small batch field configuration helper, and a Stimulus controller that only manages editing state, focus, submit timing, and cancel behavior.

**Tech Stack:** Rails 8, ERB, Turbo/Hotwire, Stimulus, Minitest controller/view tests, existing ERP styles and I18n

---

## File Map

- Modify: `app/controllers/erp/sku_batches_controller.rb`
  - Add Turbo Stream inline-update handling while preserving existing HTML modal flow.
- Create: `app/controllers/concerns/inline_editable_response.rb`
  - Centralize single-field Turbo inline update validation and success/failure stream rendering helpers.
- Create: `app/helpers/erp/inline_edit_helper.rb`
  - Hold reusable frame-id, feedback-target, display-formatting, and batch editable-field config helpers.
- Create: `app/views/shared/_inline_edit_cell.html.erb`
  - Render shared display/edit states for one inline-editable cell.
- Create: `app/views/shared/_inline_edit_feedback.html.erb`
  - Render localized success/error feedback for one batch section.
- Modify: `app/views/erp/skus/index.html.erb`
  - Replace editable batch cells with shared inline-edit cells and add feedback containers.
- Create: `app/javascript/controllers/inline_cell_controller.js`
  - Handle click-to-edit, auto-submit, Escape cancel, and duplicate-submit protection.
- Modify: `app/javascript/application.js`
  - Register the new Stimulus controller.
- Modify: `app/assets/stylesheets/application.css`
  - Add inline-edit cell and feedback styling without changing existing table layout more than necessary.
- Modify: `config/locales/zh.yml`
  - Add any new user-visible inline-edit feedback and accessibility text.
- Modify: `config/locales/en.yml`
  - Add matching English translations.
- Modify: `config/locales/ru.yml`
  - Add matching Russian translations.
- Test: `test/controllers/erp/sku_batches_controller_test.rb`
  - Add Turbo Stream success/failure tests for inline cell updates.
- Test: `test/controllers/erp/skus_controller_test.rb`
  - Add rendering assertions for inline-edit cell frames/hooks on batch rows.

## Task 1: Add Failing Turbo Inline Update Tests

**Files:**
- Modify: `test/controllers/erp/sku_batches_controller_test.rb`
- Test: `test/controllers/erp/sku_batches_controller_test.rb`

- [ ] **Step 1: Write the failing success-path Turbo Stream test**

Add a test like this near the existing `update` tests in `test/controllers/erp/sku_batches_controller_test.rb`:

```ruby
  test "inline update returns turbo stream cell and feedback on success" do
    patch "/erp/sku_batches/#{@batch.id}",
      params: {
        inline_field: "status",
        inline_context: {
          frame_id: "sku_batch_#{@batch.id}_status_cell",
          feedback_target: "batch-inline-feedback--sku-#{@sku.id}"
        },
        ec_sku_batch: {
          status: "received"
        }
      },
      headers: {
        "Accept" => "text/vnd.turbo-stream.html"
      }

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html; charset=utf-8", response.media_type + "; charset=utf-8"

    @batch.reload
    assert_equal "received", @batch.status
    assert_includes response.body, %(target="sku_batch_#{@batch.id}_status_cell")
    assert_includes response.body, %(target="batch-inline-feedback--sku-#{@sku.id}")
    assert_includes response.body, "received"
  end
```

- [ ] **Step 2: Write the failing failure-path Turbo Stream test**

Add a second test in the same file:

```ruby
  test "inline update keeps edit state and feedback on failure" do
    patch "/erp/sku_batches/#{@batch.id}",
      params: {
        inline_field: "batch_code",
        inline_context: {
          frame_id: "sku_batch_#{@batch.id}_batch_code_cell",
          feedback_target: "batch-inline-feedback--sku-#{@sku.id}"
        },
        ec_sku_batch: {
          batch_code: ""
        }
      },
      headers: {
        "Accept" => "text/vnd.turbo-stream.html"
      }

    assert_response :unprocessable_entity

    @batch.reload
    assert_equal "ERP-BATCH-#{@token}", @batch.batch_code
    assert_includes response.body, %(target="sku_batch_#{@batch.id}_batch_code_cell")
    assert_includes response.body, %(target="batch-inline-feedback--sku-#{@sku.id}")
    assert_includes response.body, "error-box"
  end
```

- [ ] **Step 3: Run the targeted controller test file to verify RED**

Run:

```bash
SKIP_JS_BUILD=1 bundle exec ruby bin/rails test test/controllers/erp/sku_batches_controller_test.rb
```

Expected:

- FAIL because Turbo Stream inline behavior is not implemented yet
- Existing modal update tests may still pass

- [ ] **Step 4: Commit the failing test scaffold**

```bash
git add test/controllers/erp/sku_batches_controller_test.rb
git commit -m "test: cover sku batch inline turbo updates"
```

## Task 2: Add Failing `/erp/skus` Inline Cell Rendering Test

**Files:**
- Modify: `test/controllers/erp/skus_controller_test.rb`
- Test: `test/controllers/erp/skus_controller_test.rb`

- [ ] **Step 1: Write the failing batch inline cell rendering test**

Add a rendering test in `test/controllers/erp/skus_controller_test.rb` after the batch-row assertions:

```ruby
  test "inventory batch rows render inline editable cell frames" do
    get "/erp/skus", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "turbo-frame#sku_batch_#{@batch.id}_batch_code_cell"
    assert_select "turbo-frame#sku_batch_#{@batch.id}_expected_arrival_on_cell"
    assert_select "turbo-frame#sku_batch_#{@batch.id}_received_on_cell"
    assert_select "turbo-frame#sku_batch_#{@batch.id}_purchased_quantity_cell"
    assert_select "turbo-frame#sku_batch_#{@batch.id}_received_quantity_cell"
    assert_select "turbo-frame#sku_batch_#{@batch.id}_status_cell"
    assert_select "#batch-inline-feedback--sku-#{@sku.id}"
  end
```

- [ ] **Step 2: Keep purchase date explicitly read-only in the test**

Extend the same test with a plain-text assertion rather than a frame assertion:

```ruby
    assert_select "turbo-frame#sku_batch_#{@batch.id}_purchase_date_cell", count: 0
    assert_match @batch.created_at.to_date.to_s, response.body
```

- [ ] **Step 3: Run the targeted SKU page test file to verify RED**

Run:

```bash
SKIP_JS_BUILD=1 bundle exec ruby bin/rails test test/controllers/erp/skus_controller_test.rb
```

Expected:

- FAIL because `/erp/skus` does not render inline cell frames yet

- [ ] **Step 4: Commit the failing render test**

```bash
git add test/controllers/erp/skus_controller_test.rb
git commit -m "test: cover inline batch cells on sku page"
```

## Task 3: Add Reusable Inline Edit Helper and Shared Partials

**Files:**
- Create: `app/helpers/erp/inline_edit_helper.rb`
- Create: `app/views/shared/_inline_edit_cell.html.erb`
- Create: `app/views/shared/_inline_edit_feedback.html.erb`

- [ ] **Step 1: Add the helper module with batch field config**

Create `app/helpers/erp/inline_edit_helper.rb`:

```ruby
module Erp
  module InlineEditHelper
    BATCH_INLINE_FIELDS = {
      batch_code: {
        input_kind: :text,
        value_key: :batch_code
      },
      expected_arrival_on: {
        input_kind: :date,
        value_key: :expected_arrival_on
      },
      received_on: {
        input_kind: :date,
        value_key: :received_on
      },
      purchased_quantity: {
        input_kind: :number,
        value_key: :purchased_quantity,
        align: :right
      },
      received_quantity: {
        input_kind: :number,
        value_key: :received_quantity,
        align: :right
      },
      status: {
        input_kind: :select,
        value_key: :status
      }
    }.freeze

    def sku_batch_inline_frame_id(batch, field)
      "sku_batch_#{batch.id}_#{field}_cell"
    end

    def sku_batch_inline_feedback_target(sku)
      "batch-inline-feedback--sku-#{sku.id}"
    end

    def sku_batch_inline_config(field)
      BATCH_INLINE_FIELDS.fetch(field.to_sym)
    end

    def sku_batch_inline_display_value(batch, field)
      case field.to_sym
      when :expected_arrival_on, :received_on
        erp_value(batch.public_send(field))
      when :status
        batch.status
      else
        batch.public_send(field)
      end
    end

    def sku_batch_inline_options(field)
      return Ec::SkuBatch::STATUSES.map { |status| [status, status] } if field.to_sym == :status

      []
    end
  end
end
```

- [ ] **Step 2: Add the shared feedback partial**

Create `app/views/shared/_inline_edit_feedback.html.erb`:

```erb
<% if message.present? %>
  <div class="inline-edit-feedback inline-edit-feedback--<%= tone %>" role="status" aria-live="polite">
    <%= message %>
  </div>
<% else %>
  <div class="inline-edit-feedback inline-edit-feedback--empty" aria-hidden="true"></div>
<% end %>
```

- [ ] **Step 3: Add the shared inline cell partial**

Create `app/views/shared/_inline_edit_cell.html.erb`:

```erb
<%= turbo_frame_tag frame_id do %>
  <% if editing %>
    <div class="inline-edit-cell inline-edit-cell--editing" data-controller="inline-cell">
      <%= form_with model: record, url: update_path, method: :patch do |form| %>
        <%= hidden_field_tag :inline_field, field %>
        <%= hidden_field_tag "inline_context[frame_id]", frame_id %>
        <%= hidden_field_tag "inline_context[feedback_target]", feedback_target %>
        <% case input_kind.to_sym
           when :text %>
          <%= form.text_field field, value: value, class: "inline-edit-cell__input", data: { inline_cell_target: "input", action: "keydown->inline-cell#handleKeydown blur->inline-cell#submit" }, aria: { label: label } %>
        <% when :number %>
          <%= form.number_field field, value: value, class: "inline-edit-cell__input inline-edit-cell__input--number", data: { inline_cell_target: "input", action: "keydown->inline-cell#handleKeydown blur->inline-cell#submit" }, aria: { label: label } %>
        <% when :date %>
          <%= form.date_field field, value: value, class: "inline-edit-cell__input", data: { inline_cell_target: "input", action: "keydown->inline-cell#handleKeydown blur->inline-cell#submit change->inline-cell#submit" }, aria: { label: label } %>
        <% when :select %>
          <%= form.select field, options_for_select(options, value), {}, class: "inline-edit-cell__input", data: { inline_cell_target: "input", action: "keydown->inline-cell#handleKeydown change->inline-cell#submit blur->inline-cell#submit" }, aria: { label: label } %>
        <% end %>
      <% end %>
      <% if error_messages.present? %>
        <div class="inline-edit-cell__error error-box"><%= error_messages.join("；") %></div>
      <% end %>
    </div>
  <% else %>
    <button type="button" class="inline-edit-cell inline-edit-cell--display <%= "inline-edit-cell--align-right" if align == :right %>" data-controller="inline-cell" data-action="inline-cell#activate" data-inline-cell-edit-url-value="<%= edit_url %>">
      <span><%= display_value.presence || "-" %></span>
    </button>
  <% end %>
<% end %>
```

- [ ] **Step 4: Run both failing test files to verify they still fail for the expected missing behavior**

Run:

```bash
SKIP_JS_BUILD=1 bundle exec ruby bin/rails test test/controllers/erp/sku_batches_controller_test.rb test/controllers/erp/skus_controller_test.rb
```

Expected:

- Still FAIL
- Failures now shift closer to missing controller/view wiring

- [ ] **Step 5: Commit the reusable helper and partial scaffolding**

```bash
git add app/helpers/erp/inline_edit_helper.rb app/views/shared/_inline_edit_cell.html.erb app/views/shared/_inline_edit_feedback.html.erb
git commit -m "feat: add shared inline edit cell scaffolding"
```

## Task 4: Add Turbo Inline Update Concern and Controller Wiring

**Files:**
- Create: `app/controllers/concerns/inline_editable_response.rb`
- Modify: `app/controllers/erp/sku_batches_controller.rb`

- [ ] **Step 1: Add the reusable concern**

Create `app/controllers/concerns/inline_editable_response.rb`:

```ruby
module InlineEditableResponse
  extend ActiveSupport::Concern

  private

  def inline_edit_request?
    request.format.turbo_stream? && params[:inline_field].present?
  end

  def inline_field_name(allowed_fields)
    field = params[:inline_field].to_s
    return field if allowed_fields.include?(field)

    raise ActionController::BadRequest, "Unsupported inline field"
  end

  def inline_context_param(key)
    params.fetch(:inline_context, {}).to_h[key.to_s]
  end

  def render_inline_edit_success(frame_id:, feedback_target:, cell_partial:, cell_locals:, message:)
    render turbo_stream: [
      turbo_stream.replace(frame_id, partial: cell_partial, locals: cell_locals),
      turbo_stream.replace(
        feedback_target,
        partial: "shared/inline_edit_feedback",
        locals: { tone: :success, message: message }
      )
    ]
  end

  def render_inline_edit_failure(frame_id:, feedback_target:, cell_partial:, cell_locals:, message:)
    render status: :unprocessable_entity, turbo_stream: [
      turbo_stream.replace(frame_id, partial: cell_partial, locals: cell_locals),
      turbo_stream.replace(
        feedback_target,
        partial: "shared/inline_edit_feedback",
        locals: { tone: :error, message: message }
      )
    ]
  end
end
```

- [ ] **Step 2: Include the concern and split update flow**

Modify `app/controllers/erp/sku_batches_controller.rb` so the top of the class includes the concern and `update` branches:

```ruby
module Erp
  class SkuBatchesController < BaseController
    include InlineEditableResponse

    INLINE_EDITABLE_FIELDS = %w[
      batch_code
      expected_arrival_on
      received_on
      purchased_quantity
      received_quantity
      status
    ].freeze
```

Then change `update`:

```ruby
    def update
      return update_inline_field if inline_edit_request?

      if @batch.update(batch_params)
        redirect_to erp_skus_path
      else
        load_sku_options
        render_modal_or_page(:edit, :edit_modal, status: :unprocessable_entity)
      end
    end
```

- [ ] **Step 3: Add the inline update private method**

Add this private method in the same controller:

```ruby
    def update_inline_field
      field = inline_field_name(INLINE_EDITABLE_FIELDS)
      frame_id = inline_context_param(:frame_id)
      feedback_target = inline_context_param(:feedback_target)

      permitted_value = params.require(:ec_sku_batch).permit(field)[field]

      if @batch.update(field => permitted_value)
        render_inline_edit_success(
          frame_id: frame_id,
          feedback_target: feedback_target,
          cell_partial: "shared/inline_edit_cell",
          cell_locals: inline_cell_locals(@batch, field, feedback_target, editing: false),
          message: I18n.t("erp.inline_edit.messages.saved")
        )
      else
        render_inline_edit_failure(
          frame_id: frame_id,
          feedback_target: feedback_target,
          cell_partial: "shared/inline_edit_cell",
          cell_locals: inline_cell_locals(@batch, field, feedback_target, editing: true),
          message: I18n.t("erp.inline_edit.messages.save_failed")
        )
      end
    end
```

- [ ] **Step 4: Add a local cell-locals builder in the controller**

Add this private helper in the controller:

```ruby
    def inline_cell_locals(batch, field, feedback_target, editing:)
      helper = view_context
      config = helper.sku_batch_inline_config(field)

      {
        record: batch,
        field: field,
        frame_id: helper.sku_batch_inline_frame_id(batch, field),
        feedback_target: feedback_target,
        update_path: erp_sku_batch_path(batch, current_locale_params),
        edit_url: erp_sku_batch_path(batch, current_locale_params.merge(inline_field: field, edit_inline: true, inline_context: { feedback_target: feedback_target })),
        label: I18n.t("erp.sku_batches.fields.#{field}"),
        input_kind: config[:input_kind],
        value: params.dig(:ec_sku_batch, field).presence || batch.public_send(field),
        display_value: helper.sku_batch_inline_display_value(batch, field),
        options: helper.sku_batch_inline_options(field),
        editing: editing,
        error_messages: batch.errors[field],
        align: config[:align]
      }
    end
```

- [ ] **Step 5: Run the controller test file to verify GREEN for inline responses**

Run:

```bash
SKIP_JS_BUILD=1 bundle exec ruby bin/rails test test/controllers/erp/sku_batches_controller_test.rb
```

Expected:

- The new inline success/failure tests PASS
- Existing batch controller tests remain green

- [ ] **Step 6: Commit the controller-side inline update behavior**

```bash
git add app/controllers/concerns/inline_editable_response.rb app/controllers/erp/sku_batches_controller.rb
git commit -m "feat: support turbo inline updates for sku batches"
```

## Task 5: Add Edit-State GET Rendering for One Cell

**Files:**
- Modify: `app/controllers/erp/sku_batches_controller.rb`
- Modify: `app/views/shared/_inline_edit_cell.html.erb`

- [ ] **Step 1: Add a GET edit-inline response in `show` or `edit` path selection**

Modify `Erp::SkuBatchesController#edit` to support cell editing when `params[:edit_inline]` is present:

```ruby
    def edit
      if params[:edit_inline].present?
        field = inline_field_name(INLINE_EDITABLE_FIELDS)
        feedback_target = params.dig(:inline_context, :feedback_target)

        render partial: "shared/inline_edit_cell",
          locals: inline_cell_locals(@batch, field, feedback_target, editing: true)
        return
      end

      load_sku_options
      render_modal_or_page(:edit, :edit_modal)
    end
```

- [ ] **Step 2: Point display-state edit URLs to the inline edit endpoint**

Update the `edit_url` construction in `inline_cell_locals` to use the edit route:

```ruby
        edit_url: erp_edit_sku_batch_path(
          batch,
          current_locale_params.merge(
            inline_field: field,
            edit_inline: true,
            inline_context: { feedback_target: feedback_target }
          )
        ),
```

- [ ] **Step 3: Ensure the shared partial can render without outer layout when editing**

Keep `shared/_inline_edit_cell.html.erb` frame-rooted exactly as the response body so the GET edit request can replace the frame directly. If needed, keep the root:

```erb
<%= turbo_frame_tag frame_id do %>
  ...
<% end %>
```

- [ ] **Step 4: Re-run batch controller tests**

Run:

```bash
SKIP_JS_BUILD=1 bundle exec ruby bin/rails test test/controllers/erp/sku_batches_controller_test.rb
```

Expected:

- PASS
- No regression in existing modal edit behavior

- [ ] **Step 5: Commit the edit-state cell rendering path**

```bash
git add app/controllers/erp/sku_batches_controller.rb app/views/shared/_inline_edit_cell.html.erb
git commit -m "feat: render inline sku batch edit cells"
```

## Task 6: Render Inline Cells and Feedback on `/erp/skus`

**Files:**
- Modify: `app/views/erp/skus/index.html.erb`

- [ ] **Step 1: Add a feedback container above each batch table**

In both batch table sections in `app/views/erp/skus/index.html.erb`, add:

```erb
<%= tag.div id: sku_batch_inline_feedback_target(sku) do %>
  <%= render "shared/inline_edit_feedback", tone: :empty, message: nil %>
<% end %>
```

Place it inside the `.batch-shell`, under `.batch-h` and above the table.

- [ ] **Step 2: Replace the editable cells in the main nested batch table**

For the nested batch rows, replace plain values with shared partial rendering:

```erb
<td>
  <%= render "shared/inline_edit_cell",
    record: batch,
    field: :batch_code,
    frame_id: sku_batch_inline_frame_id(batch, :batch_code),
    feedback_target: sku_batch_inline_feedback_target(sku),
    update_path: erp_sku_batch_path(batch, current_locale_params),
    edit_url: erp_edit_sku_batch_path(batch, current_locale_params.merge(inline_field: :batch_code, edit_inline: true, inline_context: { feedback_target: sku_batch_inline_feedback_target(sku) })),
    label: t("erp.sku_batches.fields.batch_code"),
    input_kind: sku_batch_inline_config(:batch_code)[:input_kind],
    value: batch.batch_code,
    display_value: sku_batch_inline_display_value(batch, :batch_code),
    options: sku_batch_inline_options(:batch_code),
    editing: false,
    error_messages: [],
    align: nil %>
</td>
```

Repeat the same pattern for:

- `expected_arrival_on`
- `received_on`
- `purchased_quantity`
- `received_quantity`
- `status`

Keep purchase date as:

```erb
<td><span class="barcode"><%= erp_value(batch.created_at&.to_date) %></span></td>
```

- [ ] **Step 3: Apply the same rendering to orphan batch rows**

Repeat the exact inline-edit rendering for the orphan SKU batch table section using the same helper methods and feedback target.

- [ ] **Step 4: Run the SKU page test file to verify GREEN**

Run:

```bash
SKIP_JS_BUILD=1 bundle exec ruby bin/rails test test/controllers/erp/skus_controller_test.rb
```

Expected:

- PASS for the new frame assertions
- Existing `/erp/skus` page tests remain green

- [ ] **Step 5: Commit the `/erp/skus` inline rendering changes**

```bash
git add app/views/erp/skus/index.html.erb
git commit -m "feat: render inline editable batch cells on sku page"
```

## Task 7: Add Stimulus Controller and Register It

**Files:**
- Create: `app/javascript/controllers/inline_cell_controller.js`
- Modify: `app/javascript/application.js`

- [ ] **Step 1: Add the Stimulus controller**

Create `app/javascript/controllers/inline_cell_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["input"];
  static values = {
    editUrl: String
  };

  connect() {
    this.submitting = false;

    if (this.hasInputTarget) {
      this.inputTarget.focus();
      this.inputTarget.select?.();
    }
  }

  activate() {
    if (!this.hasEditUrlValue) return;

    this.element.disabled = true;
    this.element.closest("turbo-frame")?.setAttribute("src", this.editUrlValue);
  }

  handleKeydown(event) {
    if (event.key === "Escape") {
      event.preventDefault();
      this.cancel();
    }

    if (event.key === "Enter") {
      event.preventDefault();
      this.submit();
    }
  }

  submit() {
    if (this.submitting) return;
    const form = this.element.querySelector("form");
    if (!form) return;

    this.submitting = true;
    form.requestSubmit();
  }

  cancel() {
    const frame = this.element.closest("turbo-frame");
    if (!frame) return;

    frame.removeAttribute("src");
    frame.reload();
  }
}
```

- [ ] **Step 2: Register the Stimulus controller**

Modify `app/javascript/application.js`:

```javascript
import InlineCellController from "./controllers/inline_cell_controller";
```

and:

```javascript
Stimulus.register("inline-cell", InlineCellController);
```

- [ ] **Step 3: Run the existing controller test files to ensure no server-side regression**

Run:

```bash
SKIP_JS_BUILD=1 bundle exec ruby bin/rails test test/controllers/erp/sku_batches_controller_test.rb test/controllers/erp/skus_controller_test.rb
```

Expected:

- PASS
- No new server-side test failures from JS registration changes

- [ ] **Step 4: Commit the Stimulus controller**

```bash
git add app/javascript/controllers/inline_cell_controller.js app/javascript/application.js
git commit -m "feat: add inline cell stimulus controller"
```

## Task 8: Add Styling and Translations

**Files:**
- Modify: `app/assets/stylesheets/application.css`
- Modify: `config/locales/zh.yml`
- Modify: `config/locales/en.yml`
- Modify: `config/locales/ru.yml`

- [ ] **Step 1: Add localized inline-edit messages**

In each locale file, add keys like:

```yml
erp:
  inline_edit:
    messages:
      saved: "已保存"
      save_failed: "保存失败，请检查输入"
```

For English:

```yml
erp:
  inline_edit:
    messages:
      saved: "Saved"
      save_failed: "Save failed. Please check the input."
```

For Russian:

```yml
erp:
  inline_edit:
    messages:
      saved: "Сохранено"
      save_failed: "Не удалось сохранить. Проверьте значение."
```

- [ ] **Step 2: Add inline-edit accessibility labels if needed**

If the shared cell partial needs explicit label text beyond existing field labels, add locale keys such as:

```yml
      edit_field: "编辑 %{field}"
```

and equivalents in English and Russian, then wire them into the partial.

- [ ] **Step 3: Add inline-edit cell and feedback styles**

Append CSS in `app/assets/stylesheets/application.css` near the existing ERP table styles:

```css
.inline-edit-feedback {
  margin: 0 0 10px;
  padding: 8px 10px;
  border-radius: 8px;
  font-size: 12px;
}

.inline-edit-feedback--empty {
  display: none;
}

.inline-edit-feedback--success {
  background: #edfdf3;
  color: #166534;
}

.inline-edit-feedback--error {
  background: #fef2f2;
  color: #991b1b;
}

.inline-edit-cell {
  width: 100%;
  min-height: 32px;
  border: 0;
  background: transparent;
  text-align: left;
  padding: 6px 8px;
}

.inline-edit-cell--display {
  cursor: pointer;
}

.inline-edit-cell--display:hover {
  background: var(--gray-50);
}

.inline-edit-cell--align-right {
  text-align: right;
}

.inline-edit-cell__input {
  width: 100%;
}

.inline-edit-cell__input--number {
  text-align: right;
}

.inline-edit-cell__error {
  margin-top: 6px;
  font-size: 11px;
}
```

- [ ] **Step 4: Run the two relevant controller test files again**

Run:

```bash
SKIP_JS_BUILD=1 bundle exec ruby bin/rails test test/controllers/erp/sku_batches_controller_test.rb test/controllers/erp/skus_controller_test.rb
```

Expected:

- PASS

- [ ] **Step 5: Commit translations and styling**

```bash
git add app/assets/stylesheets/application.css config/locales/zh.yml config/locales/en.yml config/locales/ru.yml
git commit -m "feat: style and localize inline batch editing"
```

## Task 9: Run Focused Verification

**Files:**
- Test: `test/controllers/erp/sku_batches_controller_test.rb`
- Test: `test/controllers/erp/skus_controller_test.rb`

- [ ] **Step 1: Run the batch controller test file**

Run:

```bash
SKIP_JS_BUILD=1 bundle exec ruby bin/rails test test/controllers/erp/sku_batches_controller_test.rb
```

Expected:

- PASS

- [ ] **Step 2: Run the SKU page controller test file**

Run:

```bash
SKIP_JS_BUILD=1 bundle exec ruby bin/rails test test/controllers/erp/skus_controller_test.rb
```

Expected:

- PASS

- [ ] **Step 3: Run both together for a final combined check**

Run:

```bash
SKIP_JS_BUILD=1 bundle exec ruby bin/rails test test/controllers/erp/sku_batches_controller_test.rb test/controllers/erp/skus_controller_test.rb
```

Expected:

- PASS
- No regressions in batch modal or SKU list rendering paths

- [ ] **Step 4: Commit verification-only follow-ups if any**

```bash
git add app/controllers/erp/sku_batches_controller.rb app/views/erp/skus/index.html.erb app/views/shared/_inline_edit_cell.html.erb app/helpers/erp/inline_edit_helper.rb app/javascript/controllers/inline_cell_controller.js app/assets/stylesheets/application.css config/locales/zh.yml config/locales/en.yml config/locales/ru.yml test/controllers/erp/sku_batches_controller_test.rb test/controllers/erp/skus_controller_test.rb
git commit -m "test: finalize inline batch edit verification"
```

## Self-Review

- Spec coverage:
  - Inline editing on `/erp/skus`: covered by Tasks 4, 5, and 6
  - Immediate single-cell save: covered by Tasks 3, 4, and 7
  - Server-driven validation and rendering: covered by Tasks 3 and 4
  - Cell-level and table-level failure feedback: covered by Tasks 3, 4, 6, and 8
  - Reusable abstraction for future list editing: covered by Tasks 3 and 4
  - Minimal automated coverage: covered by Tasks 1, 2, and 9
- Placeholder scan:
  - No `TODO`, `TBD`, or deferred implementation markers remain
- Type consistency:
  - `inline_field`, `inline_context`, frame id naming, feedback target naming, helper method naming, and shared partial names are consistent across tasks

## Notes for Execution

- Keep the existing modal edit flow working exactly as before for non-inline fields.
- Do not add purchase-date inline editing; it is intentionally read-only in this plan.
- Do not expand inline editing to `/erp/sku_batches` in this implementation.
- Use `apply_patch` for file edits.
- Only stage task-relevant files at each commit because the worktree may already contain unrelated changes.
