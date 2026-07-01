# Store Product Operators Design

## Goal

Allow store platform products to be assigned to one or more operation users. The binding is managed from the store detail page and uses real `User` records, not free-text names.

## Scope

- Add a many-to-many assignment between `Ec::SkuProduct` and `User`.
- Add a store detail page at `/erp/stores/:id`.
- Show all SKU product bindings for that store on the detail page.
- Let users with `manage_skus` update the operators for a single store product.
- Keep visible UI text in Rails I18n.

Out of scope:

- Editing raw platform products.
- Adding product-to-operator filters to reports.
- Migrating existing `Ec::Sku#owner_name`.
- Creating new users from the store detail page.

## Data Model

Create `ec_sku_product_operators` with:

- `sku_product_id`, required, foreign key to `ec_sku_products`.
- `user_id`, required, foreign key to `users`.
- timestamps.
- unique index on `[sku_product_id, user_id]`.

Model relationships:

- `Ec::SkuProduct has_many :operator_assignments`.
- `Ec::SkuProduct has_many :operators, through: :operator_assignments, source: :user`.
- `User has_many :sku_product_operator_assignments`.
- `User has_many :operated_sku_products, through: :sku_product_operator_assignments, source: :sku_product`.

The join model validates presence and uniqueness of `[sku_product_id, user_id]`.

## Store Detail Page

`Erp::StoresController#show` loads:

- the store;
- its `Ec::SkuProduct` rows, including SKU, store, and operators;
- active users as operator candidates.

The page shows:

- store summary fields already used elsewhere: public store ID, platform, name, company type, registration country, active status, memo;
- a table of platform products bound to that store;
- product fields: SKU code, product ID, offer ID, product name, current operators, product attribute link, platform edit link;
- for users with `manage_skus`, a compact form per product to save operator IDs.

The store list links each store name or a row action to the detail page. Existing edit modal behavior remains unchanged.

## Updating Operators

Add a nested route under stores, for example:

`patch /erp/stores/:store_id/sku_products/:id/operators`

Controller behavior:

- requires `manage_skus`;
- finds the product through the current store, so a product from another store cannot be updated through this URL;
- permits `operator_ids: []`;
- keeps only active users as valid candidates;
- replaces the product's operator collection with the selected users;
- redirects back to the store detail page.

If no operators are selected, the product has zero operators. This is allowed because some products may not be assigned yet.

## Permissions

- Viewing the detail page uses existing ERP access: `view_erp`.
- Updating operators requires existing `manage_skus`.
- The candidate user list includes active users. Users with the `operator` role are ordered first, then other active users by email.

## Tests

Add focused controller/integration tests:

- store detail renders store fields, product rows, current operators, and management forms for a `manage_skus` user;
- store detail renders product rows without management forms for a read-only ERP user;
- updating operators replaces the assigned user set;
- updating through the wrong store returns not found or does not change the assignment.

Run:

```bash
rbenv exec ruby bin/rails test test/controllers/erp/stores_controller_test.rb
```
