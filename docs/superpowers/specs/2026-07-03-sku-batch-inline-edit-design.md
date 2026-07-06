# SKU Batch Inline Edit Design

## Context

The `/erp/skus` page currently shows batch details inside the third expansion level:

- `Master SKU`
- `SKU`
- `Batch list`

Batch rows are read-only in the list. Users can only edit a batch by clicking the right-side edit action and using the modal form handled by `Erp::SkuBatchesController#edit` and `#update`.

The requested behavior is to support inline editing directly inside the batch list for fields already visible in the table, with immediate save after a single cell is edited.

## Goals

- Allow inline editing directly inside the batch list on `/erp/skus`
- Save immediately after a single cell is changed
- Keep validation and formatting server-driven
- Show both cell-level error feedback and table-level feedback on failure
- Abstract the interaction so it can be reused in other list views later

## Non-Goals

- Do not convert the whole row into edit mode
- Do not add new editable columns to the batch list in this change
- Do not remove the existing modal edit entry
- Do not apply the new pattern to `/erp/sku_batches` index yet
- Do not introduce a client-heavy table editing framework

## Editable Scope

Inline editing will be added only for batch fields already displayed in the `/erp/skus` batch table and backed by editable attributes:

- `batch_code`
- `expected_arrival_on`
- `received_on`
- `purchased_quantity`
- `received_quantity`
- `status`

The following currently displayed column remains read-only:

- purchase date column, because it currently renders `created_at.to_date` and is not an editable form field

The following batch fields remain editable only through the existing modal form:

- `sku_code`
- `purchase_unit_price_cny`
- `memo`

## Chosen Approach

Use Turbo-frame-based per-cell inline editing with a small reusable rendering contract.

Each editable cell has two states:

1. Display state
   - Rendered as a clickable value
   - Lives inside a dedicated `turbo_frame_tag`
2. Edit state
   - Replaces only that cell with a compact form
   - Submits a single field update immediately

This keeps the behavior aligned with the Rails + Turbo architecture already used in the project. Validation, formatting, authorization, and response rendering remain on the server side.

## Alternatives Considered

### 1. Turbo-frame per-cell editing

Recommended.

Pros:

- Fits existing Rails + Hotwire patterns
- Keeps formatting and validation server-side
- Easy to reuse in other tables
- Failure states are straightforward

Cons:

- More partial and frame structure in markup
- More granular requests

### 2. Stimulus plus fetch inline editing

Rejected.

Pros:

- Lighter interaction once fully built

Cons:

- Pushes validation, formatting, and failure handling into JavaScript
- Harder to reuse consistently
- Moves the project toward a custom front-end editing system

### 3. Always-rendered hidden row inputs

Rejected.

Pros:

- Fast switch into edit state

Cons:

- Heavy DOM
- Harder to generalize
- Couples abstraction to one table shape

## UX Behavior

### Entry

- Clicking an editable batch cell opens that cell in edit mode
- Right-side edit action remains available for non-inline fields

### Save timing

- Text and number inputs save on blur or `Enter`
- Date inputs save on change or blur
- Select inputs save on change

### Success

- Only the edited cell is re-rendered back into display state
- A lightweight success message is shown in the batch section feedback area
- Expanded table state remains unchanged

### Failure

- The edited cell stays in edit mode
- The attempted value is preserved
- Cell-level validation error is rendered inside the cell
- A batch-section-level error message is rendered in the feedback area

### Cancel

- `Escape` exits edit mode and restores the display state without saving

## Page Integration

The change applies only to batch tables rendered inside `/erp/skus`.

### Feedback container

Each expanded batch section gets a local feedback container, for example:

- `batch-inline-feedback--sku-<sku.id>`

This container is responsible for showing the latest success or failure message for inline edits in that batch section.

### Cell frames

Each editable cell gets a dedicated Turbo frame. Example naming:

- `sku_batch_<batch.id>_batch_code_cell`
- `sku_batch_<batch.id>_status_cell`

Only the targeted cell frame is replaced after edit requests.

### Modal edit retention

The existing modal edit button remains in place because some batch fields are still outside the inline-edit scope.

## Reusable Abstraction

The feature should be implemented with reusable parts rather than hardcoding batch-only behavior into the table.

### 1. Shared inline edit cell partial

Add a shared partial such as:

- `app/views/shared/_inline_edit_cell.html.erb`

Responsibilities:

- Render display state
- Render edit state
- Support input kinds:
  - text
  - number
  - date
  - select
- Accept locals describing:
  - `record`
  - `field`
  - `value`
  - `display_value`
  - `input_kind`
  - `update_path`
  - `options`
  - `frame_id`
  - `feedback_target`
  - `editing`
  - `error_messages`

### 2. Inline edit field configuration

Add a small configuration object or helper that describes field behavior. For batch fields it should define:

- label key
- input kind
- formatting rule
- right-aligned numeric display
- select options for `status`

This keeps future resources from duplicating field metadata in views and controllers.

### 3. Stimulus controller

Add an `inline-cell` Stimulus controller for front-end interaction only.

Responsibilities:

- switch cell into edit state
- autofocus the input
- submit on blur, `Enter`, or select/date change
- cancel on `Escape`
- avoid duplicate submits while saving

This controller should not own validation rules or business formatting.

### 4. Controller response convention

Introduce a reusable controller-side pattern, likely through a concern, for single-field Turbo inline updates.

Responsibilities:

- validate `inline_field`
- restrict updates to one permitted field per request
- render turbo stream success and failure responses consistently

This pattern should be reusable by future list-inline-edit features.

## Controller Contract

`Erp::SkuBatchesController#update` will support a Turbo inline-edit path in addition to the existing HTML modal flow.

### Request shape

- `PATCH /erp/sku_batches/:id`
- `Accept: text/vnd.turbo-stream.html`
- params include:
  - `inline_field`
  - `ec_sku_batch[<field>]`
  - local UI routing metadata such as frame id or feedback target if needed

### Rules

- Only one inline-editable field may be updated per request
- The field must be on the controller whitelist
- Existing authorization remains unchanged

### Success response

Return Turbo Stream updates for:

1. the target cell frame, back in display state
2. the local feedback container, with success state

### Failure response

Return Turbo Stream updates for:

1. the target cell frame, still in edit state with validation errors
2. the local feedback container, with error state

The standard HTML redirect flow remains unchanged for modal-based edit submissions.

## Rendering Rules

### Formatting

- Reuse existing display formatting where possible
- Date values should continue to use project-consistent date rendering
- Empty values should display using the same project conventions where applicable

### Alignment

- Quantity fields remain right-aligned in both display and edit modes
- `status` remains a select in edit state and a badge or plain display token in display state depending on current table styling

### Accessibility

- Editable display state should expose a clear interactive affordance
- Inputs should have accessible labels, either visible or via aria attributes
- Error messages should be associated to the edited control

## Risks and Mitigations

### Risk: expanded rows collapse after save

Mitigation:

- replace only the target cell frame and the local feedback container
- do not re-render the whole batch row or batch table

### Risk: duplicated field-specific logic

Mitigation:

- centralize field metadata in a reusable config object/helper
- centralize response behavior in a concern or helper method

### Risk: confusing failures for immediate-save editing

Mitigation:

- preserve user input on failure
- show cell-level errors and batch-level error feedback together

### Risk: interaction complexity grows in JavaScript

Mitigation:

- keep JS limited to state toggling and submission timing
- keep validation and rendering server-side

## Test Strategy

This feature should not ship without minimal automated coverage.

Add focused Rails tests only; no browser-system suite is required for this change.

### 1. Inline update success test

Controller test for `PATCH /erp/sku_batches/:id` with Turbo Stream headers and a valid inline field.

Assert:

- record is updated
- response format is Turbo Stream
- response includes cell replacement
- response includes success feedback replacement

### 2. Inline update failure test

Controller test for invalid inline update, such as blank `batch_code`.

Assert:

- record remains valid in persisted state
- response format is Turbo Stream
- response includes edit-state cell replacement
- response includes error feedback replacement

### 3. `/erp/skus` rendering test

View/controller test for the SKU page asserting that editable batch columns render the expected frame or controller hooks.

Assert:

- editable cells exist for the configured batch fields
- non-editable purchase date column remains plain output

## Implementation Sequence

1. Add reusable inline-edit field config and shared cell partial
2. Add `inline-cell` Stimulus controller
3. Extend `Erp::SkuBatchesController#update` with Turbo inline-edit handling
4. Replace editable batch cells in `/erp/skus` with inline cell rendering
5. Add local feedback container to each expanded batch section
6. Add minimal controller/rendering tests

## Open Decisions Resolved

- Save mode: immediate save after single-cell edit
- Failure UX: keep attempted input, show cell-level error, and show batch-level error message
- Scope: only fields already visible in the current batch table, excluding read-only purchase date
- Rollout: `/erp/skus` batch tables only for now

## Expected Outcome

Users can maintain the most commonly edited batch fields directly from the SKU management batch list without opening the modal for every small adjustment, while the implementation stays aligned with the project’s Rails + Turbo architecture and provides a reusable pattern for future inline-edit list interactions.
