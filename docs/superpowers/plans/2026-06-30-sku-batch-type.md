# Sku Batch Type Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `batch_type` and `defect_offset_note` to `Ec::SkuBatch` at the database and model layers, with `batch_type` defaulting to `normal`.

**Architecture:** Use one additive migration to extend `ec_sku_batches`, then expose the requested numeric mapping through a Rails enum on `Ec::SkuBatch`. Validate the behavior through model tests only, leaving controllers and views unchanged.

**Tech Stack:** Rails 8, ActiveRecord migrations, Minitest

---

### Task 1: Add Failing Model Coverage For The New Attributes

**Files:**
- Modify: `test/models/ec/sku_batch_test.rb`
- Test: `test/models/ec/sku_batch_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
  test "defaults batch type to normal" do
    batch = Ec::SkuBatch.create!(
      sku_code: @sku.sku_code,
      batch_code: "DEFAULT-#{@token}",
      purchased_quantity: 100,
      purchase_unit_price_cny: 12.5
    )

    assert_equal "normal", batch.batch_type
    assert_nil batch.defect_offset_note
    assert_predicate batch, :normal?
  end

  test "allows assigning a non-default batch type and note" do
    batch = Ec::SkuBatch.create!(
      sku_code: @sku.sku_code,
      batch_code: "OFFSET-#{@token}",
      purchased_quantity: 100,
      purchase_unit_price_cny: 12.5,
      batch_type: :wb_fbw_offset,
      defect_offset_note: "FBW inventory reconciliation"
    )

    assert_equal "wb_fbw_offset", batch.batch_type
    assert_equal "FBW inventory reconciliation", batch.defect_offset_note
    assert_predicate batch, :wb_fbw_offset?
  end

  test "rejects invalid batch type values" do
    batch = Ec::SkuBatch.new(
      sku_code: @sku.sku_code,
      batch_code: "INVALID-#{@token}",
      purchased_quantity: 100,
      purchase_unit_price_cny: 12.5,
      batch_type: :not_real
    )

    assert_not batch.valid?
    assert_predicate batch.errors[:batch_type], :present?
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `rbenv exec ruby bin/rails test test/models/ec/sku_batch_test.rb`
Expected: FAIL because `Ec::SkuBatch` does not yet define `batch_type` / `defect_offset_note`.

- [ ] **Step 3: Keep the existing tests unchanged**

```ruby
  test "belongs to sku and normalizes batch code" do
    batch = Ec::SkuBatch.create!(
      sku_code: @sku.sku_code,
      batch_code: " batch-#{@token.downcase} ",
      purchased_quantity: 100,
      purchase_unit_price_cny: 12.5
    )

    assert_equal "BATCH-#{@token}", batch.batch_code
    assert_equal @sku, batch.sku
  end
```

This step is intentional: only append the new behavior tests so the diff stays focused.

- [ ] **Step 4: Re-run the model test file to confirm the red state is still the missing feature**

Run: `rbenv exec ruby bin/rails test test/models/ec/sku_batch_test.rb`
Expected: FAIL on the new assertions, not because of fixture/setup issues.

- [ ] **Step 5: Commit**

```bash
git add test/models/ec/sku_batch_test.rb
git commit -m "test: cover sku batch type attributes"
```

### Task 2: Implement The Migration And Model Enum

**Files:**
- Create: `db/migrate/20260630000001_add_batch_type_to_ec_sku_batches.rb`
- Modify: `app/models/ec/sku_batch.rb`
- Modify: `db/schema.rb`
- Test: `test/models/ec/sku_batch_test.rb`

- [ ] **Step 1: Write the migration**

```ruby
class AddBatchTypeToEcSkuBatches < ActiveRecord::Migration[8.0]
  def change
    add_column :ec_sku_batches, :batch_type, :integer, null: false, default: 1
    add_column :ec_sku_batches, :defect_offset_note, :string
  end
end
```

- [ ] **Step 2: Add the enum to the model**

```ruby
    enum :batch_type, {
      normal: 1,
      wb_fbw_offset: 2,
      untrackable_defective: 3,
      other: 4
    }, validate: true
```

Place it near the existing constants and validations in `app/models/ec/sku_batch.rb`.

- [ ] **Step 3: Update the model body without adding unrelated rules**

```ruby
    validates :sku_code, :batch_code, presence: true
    validates :batch_code, uniqueness: true
    validates :status, inclusion: { in: STATUSES }
    validates :purchased_quantity, :received_quantity, numericality: { greater_than_or_equal_to: 0 }
    validates :purchase_unit_price_cny, numericality: { greater_than_or_equal_to: 0 }
```

Do not add any `defect_offset_note` validation or conditional callback in this task.

- [ ] **Step 4: Run the migration via the test helper path that refreshes schema**

Run: `rbenv exec ruby bin/rails db:migrate`
Expected: migration applies cleanly and `db/schema.rb` gains both new columns on `ec_sku_batches`.

- [ ] **Step 5: Commit**

```bash
git add db/migrate/20260630000011_add_batch_type_to_ec_sku_batches.rb app/models/ec/sku_batch.rb db/schema.rb
git commit -m "feat: add sku batch type enum"
```

### Task 3: Verify The Green State

**Files:**
- Test: `test/models/ec/sku_batch_test.rb`

- [ ] **Step 1: Run the targeted model test**

Run: `rbenv exec ruby bin/rails test test/models/ec/sku_batch_test.rb`
Expected: PASS with the new enum behavior covered.

- [ ] **Step 2: Run the related controller test as a regression check**

Run: `rbenv exec ruby bin/rails test test/controllers/erp/sku_batches_controller_test.rb`
Expected: PASS because the UI contract is unchanged.

- [ ] **Step 3: Inspect the final diff**

Run: `git diff -- app/models/ec/sku_batch.rb test/models/ec/sku_batch_test.rb db/migrate/20260630000001_add_batch_type_to_ec_sku_batches.rb db/schema.rb`
Expected: only the migration, schema, model enum, and model tests are changed.

- [ ] **Step 4: Commit the verification-complete state**

```bash
git add test/models/ec/sku_batch_test.rb test/controllers/erp/sku_batches_controller_test.rb
git commit -m "test: verify sku batch type change"
```

- [ ] **Step 5: Report any residual risk explicitly**

State that:

- ERP forms and displays do not yet expose `batch_type` or `defect_offset_note`
- no business rule currently requires `defect_offset_note` for any enum value
