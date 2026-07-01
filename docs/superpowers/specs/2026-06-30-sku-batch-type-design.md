# Sku Batch Type And Defect Note Design

## Goal

Extend `Ec::SkuBatch` with two new database-backed attributes:

- `batch_type`
- `defect_offset_note`

This change is intentionally limited to the database and model layers. Existing ERP pages, controllers, and views remain unchanged for now.

## Scope

In scope:

- add columns to `ec_sku_batches`
- define the `batch_type` enum in `Ec::SkuBatch`
- add model tests for default and enum behavior

Out of scope:

- ERP form inputs
- ERP list/detail display
- any new business rules tied to specific batch types
- any validation coupling between `batch_type` and `defect_offset_note`

## Data Design

`batch_type` will be stored as an integer with the following mapping:

- `1` => `normal`
- `2` => `wb_fbw_offset`
- `3` => `untrackable_defective`
- `4` => `other`

`defect_offset_note` will be stored as a nullable string.

Database defaults:

- `batch_type`: `1`
- `defect_offset_note`: no default, nullable

## Model Design

`Ec::SkuBatch` will define:

```ruby
enum :batch_type, {
  normal: 1,
  wb_fbw_offset: 2,
  untrackable_defective: 3,
  other: 4
}, validate: true
```

This keeps the database aligned with the requested numeric codes while exposing standard Rails enum helpers such as `normal?` and assignment by symbol or string key.

No additional callbacks or validations will be added for `defect_offset_note` in this change.

## Migration Strategy

Use a single additive migration that:

1. adds `batch_type` as `integer`, `null: false`, `default: 1`
2. adds `defect_offset_note` as `string`

This is backward-compatible for existing rows because the default covers current records.

## Testing

Add model coverage for:

- newly created batches default to `normal`
- valid enum assignment works for a non-default value
- invalid `batch_type` values are rejected by model validation

Controller and view tests are intentionally unchanged because this task does not expose the new attributes through the UI yet.
