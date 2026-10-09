# Ozon Listing Automation Implementation Plan

> **面向 AI 代理的工作者：** 按任务逐个实现；每个任务先写失败测试，再实现最小改动，完成该任务的验收后再进入下一任务。除非任务明确要求，不运行前端构建或启动 Web server。

> 数据库变更必须通过 `rails generate migration` 生成；测试使用唯一 SKU/token 并显式清理，因为本项目关闭了 transactional tests。

## 目标与边界

为现有 Rails 8 ERP 增加 Ozon SKU 商品卡自动化能力，覆盖商品基础资料、类目属性、图片、价格、库存、异步任务状态、Listing 更新和 AI Agent 调用。

首期采用“Agent 生成/修改草稿 → 服务端完整校验 → 用户确认 → 后端 Job 提交 Ozon”的执行边界。Agent 不直接接触 API 凭证，也不能通过任意 URL 工具写入 Ozon。

以当前 Ozon Seller API OpenAPI 为准：

- 全量创建和更新：`POST /v3/product/import`
- 导入任务状态：`POST /v1/product/import/info`
- 属性增量更新：`POST /v1/product/attributes/update`
- 图片全量替换：`POST /v2/product/pictures/import`
- 价格：`POST /v1/product/import/prices`
- 库存：`POST /v2/products/stocks`
- 商品和审核状态：`POST /v3/product/info/list`
- 配额：`POST /v4/product/info/limit`

旧的手写 Ozon 商品文档中列出的 `/v2/product/import`、`/v2/product/validation`、`/v1/product/image/upload` 不作为新实现依据。当前 OpenAPI 没有通用商品预校验接口，因此预校验由本地目录规则完成，平台错误以 `import/info` 和商品详情接口为最终结果。

## 依赖和不变量

- `offer_id` 默认映射到内部 `Ec::Sku#sku_code`，允许草稿覆盖。
- 只有 Ozon 异步导入成功并读回 `product_id`、`sku` 后，才能创建或更新 `Ec::SkuProduct`；不能为尚未完成的任务提前创建绑定。
- 类目必须是启用的叶子类目，`type_id` 和必填属性来自 Ozon 类目目录。
- 字典属性必须使用 Ozon 返回的 `dictionary_value_id`；AI 不能自行生成字典 ID。
- Ozon 商品更新是全量覆盖；部分属性变化使用属性增量接口，涉及删除或完整替换时重新提交完整商品。
- 图片接口是全量替换，必须提交最终应保留的全部图片。
- Ozon 商品审核通过不等于前台可售；价格和库存成功后才允许标记为可售候选，最终状态以 Ozon 返回为准。
- 所有外部写操作都必须有权限检查、幂等键、审计记录和可重试状态。

## 文件总览

- Create: `db/migrate/*_create_ec_ozon_listing_publications.rb`
- Create: `app/models/ec/ozon_listing_publication.rb`
- Create: `app/services/ec/ozon_listing_draft_builder.rb`
- Create: `app/services/ec/ozon_listing_validator.rb`
- Create: `app/services/raw_ozon/listing_client.rb`
- Create: `app/jobs/raw_ozon/listing_import_job.rb`
- Create: `app/jobs/raw_ozon/listing_import_poll_job.rb`
- Create: `app/jobs/raw_ozon/listing_price_stock_job.rb`
- Modify: `app/services/raw_ozon/ozon_client.rb`
- Modify: `app/services/raw_ozon/syncs/products.rb` only if final read-back needs a focused sync helper
- Create: `app/services/erp_ai/ozon_listing_agent_context.rb`
- Modify: `app/services/erp_ai/tool_registry.rb`
- Modify: `app/services/mcp/tool_registry.rb`
- Modify: `app/services/mcp/tool_executor.rb`
- Modify: `app/models/agent.rb` if a dedicated fixed Agent is introduced
- Create/modify: Ozon listing Controller, ERB views and I18n locales
- Create: focused model, service, Job, controller and Agent tool tests

## Task 0: Freeze the API baseline and first vertical slice

**Files:**

- Create or update: `docs/platform_apis/ozon/03-商品管理.md` only after comparing it with the current official OpenAPI
- Create: `docs/platform_apis/ozon/18-商品上架自动化接口矩阵.md`

- [ ] Record the current endpoint versions, required headers, item limits, quota fields, rate-limit headers and terminal task states.
- [ ] Record that `/v3/product/import` is full create/update, `/v1/product/attributes/update` cannot delete existing values, and `/v2/product/pictures/import` replaces the complete image set.
- [ ] Record that the current OpenAPI has no general product-validation endpoint; local validation plus Ozon task errors are the validation contract.
- [ ] Define the first live-test slice as one Ozon store, one SKU, one known enabled leaf category, one confirmed draft and one test account.
- [ ] Verify the first slice can complete import, poll, read-back and binding before adding bulk UI or multi-store automation.

## Task 1: Lock the canonical draft contract

**Files:**

- Create: `app/services/ec/ozon_listing_draft_builder.rb`
- Create: `test/services/ec/ozon_listing_draft_builder_test.rb`
- Create: `test/services/ec/ozon_listing_payload_contract_test.rb`

- [ ] Define a canonical payload for one SKU/store containing identity, category/type, title, description attribute, barcode, dimensions, weight, VAT, currency, attributes, complex attributes, images, primary image, color image, price and initial stock intent.
- [ ] Map existing `Ec::Sku`, `Ec::SkuDimension`, `Ec::Attachment`, `RawOzon::Product`, `RawOzon::ProductAttribute` and `Ec::SkuProduct` data without reading order-line `sku_code` as a binding source.
- [ ] Add tests for new SKU, existing Listing, missing dimension, missing image, existing Ozon product and multi-store isolation.
- [ ] Verify generated payload contains no API key, client ID or private Rails URL.
- [ ] Commit only after the payload contract tests pass.

## Task 2: Add local category and attribute validation

**Files:**

- Create: `app/services/ec/ozon_listing_validator.rb`
- Create: `test/services/ec/ozon_listing_validator_test.rb`
- Modify: `app/services/ec/platform_product_attribute_options_query.rb` only when an existing query cannot provide a required rule

- [ ] Validate enabled leaf category, `description_category_id`, `type_id`, required attributes, collection limits and complex attribute shape using `RawOzon::CategoryAttribute` and `RawOzon::AttributeValue`.
- [ ] Validate `offer_id` length, title length, price/old-price relationship, currency, VAT, non-zero dimensions and weight, image count/order and public HTTPS image URL format.
- [ ] Support dictionary search through `/v1/description-category/attribute/values/search` and require an exact selected dictionary value before submission.
- [ ] Return structured errors with field, attribute ID, severity and remediation text; do not collapse them into one string.
- [ ] Add quota validation using `/v4/product/info/limit` before queueing a write.
- [ ] Verify the validator rejects incomplete payloads without making an external write.

## Task 3: Extend the Ozon client and persist publication state

**Files:**

- Create migration/model for `Ec::OzonListingPublication` using `rails generate migration`
- Create: `test/models/ec/ozon_listing_publication_test.rb`
- Modify: `app/services/raw_ozon/ozon_client.rb`
- Create: `app/services/raw_ozon/listing_client.rb`
- Create: `test/services/raw_ozon/listing_client_test.rb`

- [ ] Keep `Client-Id` and `Api-Key` resolution inside the server-side client.
- [ ] Add explicit methods for import, import status, attribute update, pictures import, picture status, price update, stock update, product info, quota and roles.
- [ ] Parse `Item-Retry-After` and `Item-Rate-Limit-Remaining` in addition to existing `Retry-After` handling.
- [ ] Persist draft payload, normalized checksum, Ozon task ID, state, attempts, request ID, errors, response JSON and timestamps; redact credentials in logs and stored payloads.
- [ ] Add unique idempotency protection for account + offer + operation + payload checksum.
- [ ] Add a role/permission check through `/v1/roles` before enabling write tools for an account.
- [ ] Preserve the Ozon mapping explicitly: `Ec::SkuProduct.product_id = Ozon id`, `platform_sku_id = Ozon sku`, `offer_id = seller offer_id`.
- [ ] Test 429, 5xx, malformed responses, duplicate submissions and account isolation with the existing fake-client pattern.

## Task 4: Implement asynchronous import and read-back

**Files:**

- Create: `app/jobs/raw_ozon/listing_import_job.rb`
- Create: `app/jobs/raw_ozon/listing_import_poll_job.rb`
- Create: `test/jobs/raw_ozon/listing_import_job_test.rb`
- Create: `test/jobs/raw_ozon/listing_import_poll_job_test.rb`

- [ ] Enqueue only validated and user-confirmed drafts.
- [ ] Submit batches of at most 100 items and save the returned task ID.
- [ ] Poll `pending`, `imported`, `failed` and `skipped`; treat unknown states as inspectable failures rather than success.
- [ ] Persist item-level Ozon errors including code, field, attribute ID, level and message.
- [ ] On success, call `/v3/product/info/list`, verify `is_created`, moderation and validation fields, then create/update `Ec::SkuProduct` with the returned product ID and platform SKU.
- [ ] Reconcile the returned product and attributes into `RawOzon::Product` and `RawOzon::ProductAttribute` before creating the local Listing binding.
- [ ] Run `Ec::ListingChangeRecorder` only after the before/after state is known.
- [ ] Add account + offer locking so two Jobs cannot update the same Listing concurrently.

## Task 5: Add images, price and stock orchestration

**Files:**

- Create: `app/services/ec/ozon_attachment_url_resolver.rb`
- Create: `app/jobs/raw_ozon/listing_price_stock_job.rb`
- Create: related service and Job tests
- Modify: existing Qiniu URL helper only if a long-lived Ozon staging URL is missing

- [ ] Resolve listing images to Ozon-fetchable public HTTPS URLs; never send `/rails/active_storage` or a private URL.
- [ ] Validate image extension, content type, dimensions and URL expiry; keep the final URL list in the publication record for retry and audit.
- [ ] Submit the complete image set through `/v2/product/pictures/import`; verify image task completion through `/v2/product/pictures/info` or import status.
- [ ] Set prices through `/v1/product/import/prices`, preserving `min_price` and automatic-promotion semantics.
- [ ] Wait until Ozon allows stock update, then send `/v2/products/stocks` with `product_id`, `warehouse_id`, `stock` and `quant_size`.
- [ ] Respect per-item rate limits and warehouse/account request limits.
- [ ] Verify price, stock and visibility after writes; do not call an approved-but-zero-stock item “published”.

## Task 6: Add dedicated AI Agent tools

**Files:**

- Create: `app/services/erp_ai/ozon_listing_agent_context.rb`
- Modify: `app/services/erp_ai/tool_registry.rb`
- Modify: `app/services/mcp/tool_registry.rb`
- Modify: `app/services/mcp/tool_executor.rb`
- Modify: `app/models/agent.rb` if a fixed `ozon_listing_agent` is needed
- Create: Agent tool tests

- [ ] Add read tools for preparing a draft, loading category attributes, searching dictionary values and showing current Listing state.
- [ ] Add write tools that accept only a draft/publication ID and validated structured changes.
- [ ] Require explicit confirmation state before import, image replacement, price change or stock change.
- [ ] Enforce visible SKU scope, store/account ownership and operation permissions in the executor.
- [ ] Return structured progress and errors so the Agent can explain pending, moderation, failed and ready-for-stock states.
- [ ] Keep credentials and arbitrary external URLs out of Agent context.

## Task 9: Add observability, recovery and security acceptance

- [ ] Add structured logs and counters for submission success, task duration, field errors, rate limiting, image failures, moderation failures and price/stock failures.
- [ ] Verify interrupted polling can resume from the persisted task state without re-submitting the import.
- [ ] Verify failed, timed-out and cancelled publications remain inspectable and retryable without creating half-bound Listings.
- [ ] Verify API keys are redacted from logs, Agent messages, tool results, request payload snapshots and exception messages.
- [ ] Verify system-level audit attribution is present when `Ec::ListingChangeRecorder` has no assigned operator.
- [ ] Perform the first live-account test with one SKU, then a small batch, before enabling bulk submission.

## Task 7: Add Rails page and approval flow

**Files:**

- Create/modify Ozon Listing Controller and routes
- Create ERB draft, attribute editor, image preview, task status and error partials
- Modify `config/locales/zh.yml`, `config/locales/en.yml`, `config/locales/ru.yml`
- Create controller and view tests

- [ ] Add a draft page that shows missing fields and attribute dictionary choices before submission.
- [ ] Reuse existing shared attachment, SKU/SPU, responsible-user and overlay components where applicable.
- [ ] Add explicit confirmation action for external Ozon writes.
- [ ] Show asynchronous task progress and field-level Ozon errors without hardcoded display text.
- [ ] Show audit entries and the linked `Ec::OperationAction` after success.

## Task 8: End-to-end acceptance

- [ ] Use a fake Ozon client to test create, poll, failed validation, retry, image replacement, price and stock paths.
- [ ] Verify a new SKU creates exactly one `Ec::SkuProduct` after successful read-back.
- [ ] Verify an existing Listing update preserves store/platform scoping and records before/after changes.
- [ ] Verify a failed or skipped Ozon task never creates a Listing binding and remains retryable.
- [ ] Verify duplicate Agent calls do not submit duplicate tasks.
- [ ] Verify private attachment URLs are never sent to Ozon.
- [ ] Run the focused Rails tests for all new services, Jobs, controllers and Agent tools.
- [ ] Run the relevant existing Ozon client, product sync, category attribute, SKU product and listing change recorder tests.
- [ ] Record any remaining Ozon account-level prerequisites, API role limitations and live-account verification steps.

## Completion criteria

The feature is complete when a user can select an internal SKU and Ozon store, generate a complete draft, resolve all required category attributes and images, review and confirm it, submit it asynchronously, observe Ozon errors and moderation state, set price and stock, and see the resulting Ozon product bound to the correct `Ec::SkuProduct` with an auditable change record. The Agent must be able to perform the same workflow through dedicated scoped tools without receiving credentials or bypassing confirmation.
