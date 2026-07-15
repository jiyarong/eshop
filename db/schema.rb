# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_07_15_085339) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "agent_skills", force: :cascade do |t|
    t.bigint "agent_id", null: false
    t.datetime "created_at", null: false
    t.bigint "skill_id", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_id", "skill_id"], name: "index_agent_skills_on_agent_id_and_skill_id", unique: true
    t.index ["agent_id"], name: "index_agent_skills_on_agent_id"
    t.index ["skill_id"], name: "index_agent_skills_on_skill_id"
  end

  create_table "agents", force: :cascade do |t|
    t.string "agent_type", default: "web", null: false
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.text "description", default: "", null: false
    t.boolean "enabled", default: true, null: false
    t.string "model_id", null: false
    t.string "name", null: false
    t.jsonb "recommended_prompts", default: [], null: false
    t.text "system_prompt", null: false
    t.decimal "temperature", precision: 3, scale: 2, default: "0.3", null: false
    t.boolean "thinking_enabled", default: false, null: false
    t.jsonb "tools", default: [], null: false
    t.datetime "updated_at", null: false
    t.index ["agent_type"], name: "index_agents_on_agent_type"
    t.index ["code"], name: "index_agents_on_code", unique: true
    t.index ["enabled"], name: "index_agents_on_enabled"
    t.index ["name"], name: "index_agents_on_name"
    t.check_constraint "agent_type::text = ANY (ARRAY['web'::character varying, 'client'::character varying]::text[])", name: "agents_agent_type_check"
  end

  create_table "conversations", force: :cascade do |t|
    t.bigint "agent_id", null: false
    t.string "business_object_id"
    t.string "business_object_type"
    t.jsonb "context", default: {}, null: false
    t.datetime "created_at", null: false
    t.string "module_name"
    t.jsonb "time_range", default: {}, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["agent_id"], name: "index_conversations_on_agent_id"
    t.index ["module_name", "business_object_type", "business_object_id"], name: "idx_conversations_on_erp_context"
    t.index ["user_id", "created_at"], name: "index_conversations_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_conversations_on_user_id"
  end

  create_table "ec_attachment_links", force: :cascade do |t|
    t.bigint "attachable_id", null: false
    t.string "attachable_type", null: false
    t.datetime "created_at", null: false
    t.bigint "ec_attachment_id", null: false
    t.datetime "updated_at", null: false
    t.index ["attachable_type", "attachable_id", "ec_attachment_id"], name: "idx_ec_attachment_links_unique_attachable", unique: true
    t.index ["attachable_type", "attachable_id"], name: "index_ec_attachment_links_on_attachable"
    t.index ["ec_attachment_id"], name: "index_ec_attachment_links_on_ec_attachment_id"
  end

  create_table "ec_attachments", force: :cascade do |t|
    t.integer "attach_type", null: false
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "oss_path", null: false
    t.string "qiniu_hash", null: false
    t.datetime "updated_at", null: false
    t.index ["attach_type"], name: "index_ec_attachments_on_attach_type"
    t.index ["oss_path"], name: "index_ec_attachments_on_oss_path", unique: true
    t.index ["qiniu_hash"], name: "index_ec_attachments_on_qiniu_hash"
  end

  create_table "ec_categories", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name_cn"
    t.string "name_en"
    t.string "name_ru"
    t.string "origin_language", null: false
    t.string "origin_name", null: false
    t.bigint "parent_id"
    t.string "source", null: false
    t.string "source_id", null: false
    t.string "source_type", null: false
    t.datetime "synced_at"
    t.datetime "translated_at"
    t.text "translation_error"
    t.datetime "updated_at", null: false
    t.index ["origin_language"], name: "index_ec_categories_on_origin_language"
    t.index ["parent_id"], name: "index_ec_categories_on_parent_id"
    t.index ["source", "source_type", "source_id"], name: "index_ec_categories_on_source_and_source_type_and_source_id", unique: true
    t.index ["source"], name: "index_ec_categories_on_source"
    t.index ["source_type"], name: "index_ec_categories_on_source_type"
  end

  create_table "ec_cost_allocation_items", force: :cascade do |t|
    t.decimal "amount_cny", precision: 12, scale: 4, null: false
    t.bigint "cost_allocation_id", null: false
    t.datetime "created_at", null: false
    t.text "memo"
    t.bigint "sku_batch_id", null: false
    t.datetime "updated_at", null: false
    t.index ["cost_allocation_id", "sku_batch_id"], name: "idx_ec_cost_alloc_items_unique", unique: true
    t.index ["cost_allocation_id"], name: "index_ec_cost_allocation_items_on_cost_allocation_id"
    t.index ["sku_batch_id"], name: "index_ec_cost_allocation_items_on_sku_batch_id"
  end

  create_table "ec_cost_allocations", force: :cascade do |t|
    t.date "allocated_on"
    t.string "allocation_method", null: false
    t.string "allocation_no", null: false
    t.string "cost_type", null: false
    t.datetime "created_at", null: false
    t.text "memo"
    t.string "status", default: "draft", null: false
    t.decimal "total_amount_cny", precision: 12, scale: 4, null: false
    t.datetime "updated_at", null: false
    t.index ["allocation_no"], name: "index_ec_cost_allocations_on_allocation_no", unique: true
    t.index ["cost_type"], name: "index_ec_cost_allocations_on_cost_type"
    t.index ["status"], name: "index_ec_cost_allocations_on_status"
  end

  create_table "ec_daily_exchange_rates", force: :cascade do |t|
    t.string "base_currency", default: "CNY", null: false
    t.datetime "created_at", null: false
    t.string "currency_code", null: false
    t.date "rate_date", null: false
    t.decimal "rate_from_base", precision: 18, scale: 8, null: false
    t.decimal "rate_to_base", precision: 18, scale: 8, null: false
    t.string "source", default: "cbr", null: false
    t.date "source_date"
    t.datetime "updated_at", null: false
    t.index ["rate_date", "base_currency", "currency_code"], name: "index_ec_daily_exchange_rates_unique_daily_currency", unique: true
  end

  create_table "ec_master_skus", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "ec_category_id"
    t.boolean "is_active", default: true, null: false
    t.string "master_sku_code", null: false
    t.text "memo"
    t.string "product_name"
    t.string "product_name_ru"
    t.datetime "updated_at", null: false
    t.index ["ec_category_id"], name: "index_ec_master_skus_on_ec_category_id"
    t.index ["is_active"], name: "index_ec_master_skus_on_is_active"
    t.index ["master_sku_code"], name: "index_ec_master_skus_on_master_sku_code", unique: true
  end

  create_table "ec_operation_logs", force: :cascade do |t|
    t.string "action", null: false
    t.jsonb "changeset", default: [], null: false
    t.datetime "created_at", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.bigint "user_id"
    t.index ["action"], name: "index_ec_operation_logs_on_action"
    t.index ["created_at"], name: "index_ec_operation_logs_on_created_at"
    t.index ["record_type", "record_id"], name: "index_ec_operation_logs_on_record_type_and_record_id"
    t.index ["user_id"], name: "index_ec_operation_logs_on_user_id"
  end

  create_table "ec_operation_tasks", force: :cascade do |t|
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.date "due_on"
    t.string "owner_name"
    t.string "platform"
    t.string "priority", default: "medium", null: false
    t.text "reason"
    t.string "sku_code"
    t.string "status", default: "open", null: false
    t.string "store_key"
    t.text "suggested_action"
    t.string "task_type", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["priority"], name: "index_ec_operation_tasks_on_priority"
    t.index ["sku_code"], name: "index_ec_operation_tasks_on_sku_code"
    t.index ["status"], name: "index_ec_operation_tasks_on_status"
    t.index ["task_type"], name: "index_ec_operation_tasks_on_task_type"
  end

  create_table "ec_order_fulfillments", force: :cascade do |t|
    t.string "cancel_reason_source"
    t.datetime "cancelled_at"
    t.string "cluster_from"
    t.string "cluster_to"
    t.datetime "created_at", null: false
    t.datetime "delivered_at"
    t.string "delivery_method_name"
    t.string "delivery_type_source"
    t.string "external_fulfillment_id", null: false
    t.string "fulfillment_key", null: false
    t.string "fulfillment_type", default: "unknown", null: false
    t.bigint "order_id", null: false
    t.string "platform", null: false
    t.bigint "raw_source_id"
    t.string "raw_source_type"
    t.datetime "shipped_at"
    t.string "source_status"
    t.string "source_substatus"
    t.string "status", default: "unknown", null: false
    t.bigint "store_id", null: false
    t.datetime "synced_at"
    t.string "tracking_number"
    t.datetime "updated_at", null: false
    t.string "warehouse_external_id"
    t.string "warehouse_name"
    t.index ["order_id"], name: "index_ec_order_fulfillments_on_order_id"
    t.index ["platform", "store_id", "fulfillment_key"], name: "idx_ec_order_fulfillments_unique_key", unique: true
    t.index ["raw_source_type", "raw_source_id"], name: "idx_ec_order_fulfillments_raw_source"
    t.index ["status"], name: "index_ec_order_fulfillments_on_status"
    t.index ["store_id"], name: "index_ec_order_fulfillments_on_store_id"
  end

  create_table "ec_order_items", force: :cascade do |t|
    t.decimal "commission_amount", precision: 18, scale: 2
    t.decimal "commission_percent", precision: 8, scale: 2
    t.datetime "created_at", null: false
    t.string "currency_code"
    t.decimal "discount_amount", precision: 18, scale: 2
    t.decimal "discount_percent", precision: 8, scale: 2
    t.string "external_item_id"
    t.bigint "fulfillment_id"
    t.jsonb "item_payload"
    t.string "offer_id"
    t.decimal "old_unit_price", precision: 18, scale: 2
    t.bigint "order_id", null: false
    t.decimal "payout", precision: 18, scale: 2
    t.string "platform", null: false
    t.string "platform_sku_id"
    t.string "product_name_source"
    t.integer "quantity", default: 1, null: false
    t.string "sku_code"
    t.bigint "store_id", null: false
    t.datetime "synced_at"
    t.decimal "unit_price", precision: 18, scale: 2
    t.datetime "updated_at", null: false
    t.index ["fulfillment_id"], name: "index_ec_order_items_on_fulfillment_id"
    t.index ["order_id"], name: "index_ec_order_items_on_order_id"
    t.index ["platform", "store_id", "external_item_id"], name: "idx_ec_order_items_external_item"
    t.index ["platform", "store_id", "offer_id"], name: "idx_ec_order_items_offer"
    t.index ["platform_sku_id"], name: "index_ec_order_items_on_platform_sku_id"
    t.index ["sku_code"], name: "index_ec_order_items_on_sku_code"
    t.index ["store_id"], name: "index_ec_order_items_on_store_id"
  end

  create_table "ec_order_source_links", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "fulfillment_id"
    t.bigint "item_id"
    t.bigint "order_id", null: false
    t.string "platform", null: false
    t.bigint "source_id", null: false
    t.string "source_key"
    t.string "source_role", default: "primary", null: false
    t.string "source_type", null: false
    t.datetime "synced_at"
    t.datetime "updated_at", null: false
    t.index ["fulfillment_id"], name: "index_ec_order_source_links_on_fulfillment_id"
    t.index ["item_id"], name: "index_ec_order_source_links_on_item_id"
    t.index ["order_id"], name: "index_ec_order_source_links_on_order_id"
    t.index ["platform", "source_key"], name: "idx_ec_order_source_links_source_key"
    t.index ["source_type", "source_id", "source_role"], name: "idx_ec_order_source_links_unique_source", unique: true
  end

  create_table "ec_orders", force: :cascade do |t|
    t.string "buyer_city"
    t.string "buyer_country"
    t.string "buyer_region"
    t.datetime "cancelled_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.string "external_order_id"
    t.string "external_order_number"
    t.datetime "in_process_at"
    t.boolean "is_legal_entity", default: false, null: false
    t.string "order_key", null: false
    t.string "order_status", default: "unknown", null: false
    t.datetime "ordered_at"
    t.string "payment_method_source"
    t.string "platform", null: false
    t.jsonb "source_payload"
    t.string "source_status"
    t.string "source_substatus"
    t.bigint "store_id", null: false
    t.datetime "synced_at"
    t.datetime "updated_at", null: false
    t.index ["order_status"], name: "index_ec_orders_on_order_status"
    t.index ["ordered_at"], name: "index_ec_orders_on_ordered_at"
    t.index ["platform", "store_id", "external_order_number"], name: "idx_ec_orders_external_order_number"
    t.index ["platform", "store_id", "order_key"], name: "idx_ec_orders_unique_order_key", unique: true
    t.index ["store_id"], name: "index_ec_orders_on_store_id"
  end

  create_table "ec_payment_requests", force: :cascade do |t|
    t.decimal "amount_cny", precision: 12, scale: 4, null: false
    t.datetime "approved_at"
    t.datetime "created_at", null: false
    t.text "memo"
    t.datetime "paid_at"
    t.string "payment_type", null: false
    t.bigint "purchase_order_id", null: false
    t.date "requested_on"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["payment_type"], name: "index_ec_payment_requests_on_payment_type"
    t.index ["purchase_order_id"], name: "index_ec_payment_requests_on_purchase_order_id"
    t.index ["status"], name: "index_ec_payment_requests_on_status"
  end

  create_table "ec_purchase_order_items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "memo"
    t.bigint "purchase_order_id", null: false
    t.integer "quantity", null: false
    t.bigint "sku_batch_id", null: false
    t.string "sku_code", null: false
    t.decimal "unit_price_cny", precision: 12, scale: 4, null: false
    t.datetime "updated_at", null: false
    t.index ["purchase_order_id", "sku_batch_id"], name: "idx_ec_po_items_order_batch_unique", unique: true
    t.index ["purchase_order_id"], name: "index_ec_purchase_order_items_on_purchase_order_id"
    t.index ["sku_batch_id"], name: "index_ec_purchase_order_items_on_sku_batch_id"
    t.index ["sku_code"], name: "index_ec_purchase_order_items_on_sku_code"
  end

  create_table "ec_purchase_orders", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "currency", default: "CNY", null: false
    t.text "memo"
    t.string "order_no", null: false
    t.date "ordered_on"
    t.string "status", default: "draft", null: false
    t.bigint "supplier_id", null: false
    t.datetime "updated_at", null: false
    t.index ["order_no"], name: "index_ec_purchase_orders_on_order_no", unique: true
    t.index ["status"], name: "index_ec_purchase_orders_on_status"
    t.index ["supplier_id"], name: "index_ec_purchase_orders_on_supplier_id"
  end

  create_table "ec_sku_batches", force: :cascade do |t|
    t.string "batch_code", null: false
    t.integer "batch_type", default: 1, null: false
    t.datetime "created_at", null: false
    t.string "defect_offset_note"
    t.date "expected_arrival_on"
    t.text "memo"
    t.date "purchase_date"
    t.decimal "purchase_unit_price_cny", precision: 12, scale: 4, default: "0.0", null: false
    t.integer "purchased_quantity", default: 0, null: false
    t.date "received_on"
    t.integer "received_quantity", default: 0, null: false
    t.string "sku_code", null: false
    t.string "status", default: "draft", null: false
    t.datetime "updated_at", null: false
    t.index ["batch_code"], name: "index_ec_sku_batches_on_batch_code", unique: true
    t.index ["sku_code"], name: "index_ec_sku_batches_on_sku_code"
  end

  create_table "ec_sku_categories", force: :cascade do |t|
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.boolean "is_active", default: true, null: false
    t.text "memo"
    t.string "name", null: false
    t.bigint "parent_id"
    t.integer "position", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_ec_sku_categories_on_code", unique: true
    t.index ["is_active"], name: "index_ec_sku_categories_on_is_active"
    t.index ["name"], name: "index_ec_sku_categories_on_name"
    t.index ["parent_id"], name: "index_ec_sku_categories_on_parent_id"
  end

  create_table "ec_sku_costs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.decimal "customs_duty_rate", precision: 6, scale: 4, default: "0.1"
    t.decimal "customs_misc_cny", precision: 10, scale: 4
    t.decimal "damage_rate", precision: 6, scale: 4, default: "0.0"
    t.decimal "freight_to_by_cny", precision: 10, scale: 4
    t.decimal "import_vat_rate", precision: 6, scale: 4, default: "0.2"
    t.text "memo"
    t.decimal "misc_cost_cny", precision: 10, scale: 4, default: "0.0"
    t.decimal "pkg_height_cm", precision: 8, scale: 2
    t.decimal "pkg_length_cm", precision: 8, scale: 2
    t.decimal "pkg_volume_override_l", precision: 8, scale: 4
    t.decimal "pkg_width_cm", precision: 8, scale: 2
    t.decimal "purchase_price_cny", precision: 10, scale: 4
    t.string "sku_code", null: false
    t.datetime "updated_at", null: false
    t.index ["sku_code"], name: "idx_ec_sku_costs_sku_code", unique: true
  end

  create_table "ec_sku_inventory_levels", force: :cascade do |t|
    t.integer "account_id", null: false
    t.datetime "created_at", null: false
    t.string "fulfillment_type", null: false
    t.boolean "is_latest", default: true, null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "platform", null: false
    t.integer "quantity", default: 0, null: false
    t.string "sku_code", null: false
    t.bigint "store_id"
    t.string "store_name"
    t.datetime "synced_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "warehouse_breakdown", default: [], null: false
    t.index ["sku_code", "platform", "account_id", "fulfillment_type", "synced_at"], name: "idx_ec_sku_inventory_levels_history"
    t.index ["sku_code", "platform", "account_id", "fulfillment_type"], name: "idx_ec_sku_inventory_levels_latest", unique: true, where: "is_latest"
    t.index ["sku_code"], name: "index_ec_sku_inventory_levels_on_sku_code"
  end

  create_table "ec_sku_marketing_states", force: :cascade do |t|
    t.bigint "changed_by_id"
    t.datetime "created_at", null: false
    t.datetime "effective_at", null: false
    t.datetime "ended_at"
    t.string "grade", null: false
    t.text "note"
    t.bigint "sku_id", null: false
    t.string "stage", null: false
    t.datetime "updated_at", null: false
    t.index ["changed_by_id"], name: "index_ec_sku_marketing_states_on_changed_by_id"
    t.index ["sku_id", "effective_at"], name: "idx_ec_sku_marketing_states_sku_effective"
    t.index ["sku_id"], name: "idx_ec_sku_marketing_states_current", unique: true, where: "(ended_at IS NULL)"
    t.check_constraint "ended_at IS NULL OR ended_at >= effective_at", name: "ec_sku_marketing_states_period_check"
    t.check_constraint "grade::text = ANY (ARRAY['S'::character varying, 'A'::character varying, 'B'::character varying, 'C'::character varying]::text[])", name: "ec_sku_marketing_states_grade_check"
    t.check_constraint "stage::text = ANY (ARRAY['new'::character varying, 'grw'::character varying, 'mat'::character varying, 'clr'::character varying]::text[])", name: "ec_sku_marketing_states_stage_check"
  end

  create_table "ec_sku_platform_costs", force: :cascade do |t|
    t.decimal "acquiring_rate", precision: 6, scale: 4
    t.decimal "ad_spend_rate", precision: 6, scale: 4
    t.decimal "commission_rate", precision: 6, scale: 4
    t.string "company_type", null: false
    t.datetime "created_at", null: false
    t.string "delivery_mode", null: false
    t.decimal "exchange_rate_rub_cny", precision: 8, scale: 4
    t.decimal "fbo_delivery_cny", precision: 10, scale: 4, default: "0.0"
    t.decimal "logistics_coeff", precision: 6, scale: 4
    t.decimal "min_price_rub", precision: 12, scale: 2
    t.decimal "ozon_fbs_delivery_rub", precision: 8, scale: 2
    t.decimal "ozon_fwd_base_rub", precision: 8, scale: 2
    t.decimal "ozon_fwd_per_liter_rub", precision: 8, scale: 2
    t.decimal "ozon_ret_base_rub", precision: 8, scale: 2
    t.decimal "ozon_ret_per_liter_rub", precision: 8, scale: 2
    t.decimal "ozon_warehouse_op_rub", precision: 8, scale: 2
    t.string "platform", null: false
    t.decimal "return_rate", precision: 6, scale: 4
    t.decimal "sales_tax_rate", precision: 6, scale: 4
    t.string "sku_code", null: false
    t.decimal "storage_30d_cny", precision: 10, scale: 4, default: "0.0"
    t.decimal "target_price_by_rub", precision: 12, scale: 2
    t.decimal "target_price_rf_rub", precision: 12, scale: 2
    t.decimal "target_price_rub", precision: 12, scale: 2
    t.datetime "updated_at", null: false
    t.decimal "wb_fixed_return_rate", precision: 8, scale: 6
    t.decimal "wb_logistics_base_rub", precision: 8, scale: 2
    t.decimal "wb_return_rate", precision: 8, scale: 6
    t.index ["sku_code", "platform", "delivery_mode", "company_type"], name: "idx_ec_sku_platform_costs_unique", unique: true
  end

  create_table "ec_sku_predicted_costs", force: :cascade do |t|
    t.string "cost_currency", default: "CNY", null: false
    t.decimal "cost_money", precision: 12, scale: 4, null: false
    t.datetime "created_at", null: false
    t.date "effective_from", null: false
    t.date "effective_to"
    t.text "note"
    t.string "sku_code", null: false
    t.datetime "updated_at", null: false
    t.index ["sku_code", "effective_from"], name: "idx_ec_sku_predicted_costs_sku_from"
  end

  create_table "ec_sku_product_operators", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "role", default: "operator", null: false
    t.bigint "sku_product_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["sku_product_id", "user_id"], name: "idx_ec_sku_product_operators_unique", unique: true
    t.index ["sku_product_id"], name: "index_ec_sku_product_operators_on_sku_product_id"
    t.index ["user_id"], name: "index_ec_sku_product_operators_on_user_id"
  end

  create_table "ec_sku_products", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "offer_id"
    t.string "platform", null: false
    t.string "platform_sku_id"
    t.string "product_id", null: false
    t.string "product_name"
    t.string "sku_code", null: false
    t.bigint "store_id", null: false
    t.datetime "updated_at", null: false
    t.index ["sku_code", "store_id"], name: "idx_ec_sku_products_sku_store"
    t.index ["store_id", "product_id"], name: "idx_ec_sku_products_unique_store_product", unique: true
    t.index ["store_id"], name: "index_ec_sku_products_on_store_id"
  end

  create_table "ec_sku_store_assignments", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "external_id"
    t.boolean "is_active", default: true, null: false
    t.date "listed_at"
    t.string "owner_name"
    t.string "platform", null: false
    t.string "sku_code", null: false
    t.string "store_key", null: false
    t.datetime "updated_at", null: false
    t.index ["owner_name"], name: "idx_ec_sku_store_assignments_owner"
    t.index ["sku_code", "store_key"], name: "idx_ec_sku_store_assignments_unique", unique: true
    t.index ["store_key"], name: "idx_ec_sku_store_assignments_store_key"
  end

  create_table "ec_skus", force: :cascade do |t|
    t.string "color"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.text "features"
    t.boolean "is_active", default: true, null: false
    t.bigint "master_sku_id"
    t.text "memo"
    t.string "model"
    t.string "owner_name"
    t.string "product_name"
    t.string "product_name_ru"
    t.string "quality_grade"
    t.string "size"
    t.bigint "sku_category_id"
    t.string "sku_code", null: false
    t.string "spec"
    t.datetime "updated_at", null: false
    t.decimal "volume_l", precision: 10, scale: 4
    t.decimal "weight_kg", precision: 10, scale: 4
    t.index ["deleted_at"], name: "index_ec_skus_on_deleted_at"
    t.index ["is_active"], name: "idx_ec_skus_is_active"
    t.index ["master_sku_id"], name: "index_ec_skus_on_master_sku_id"
    t.index ["sku_category_id"], name: "index_ec_skus_on_sku_category_id"
    t.index ["sku_code"], name: "idx_ec_skus_sku_code", unique: true
  end

  create_table "ec_stores", force: :cascade do |t|
    t.string "company_type"
    t.datetime "created_at", null: false
    t.boolean "is_active", default: true, null: false
    t.text "memo"
    t.text "ozon_api_key"
    t.string "ozon_client_id"
    t.string "ozon_performance_client_id"
    t.text "ozon_performance_client_secret"
    t.integer "ozon_raw_account_id"
    t.string "platform", null: false
    t.string "registration_country"
    t.string "store_name", null: false
    t.datetime "updated_at", null: false
    t.text "wb_api_token"
    t.integer "wb_raw_account_id"
    t.index ["ozon_client_id"], name: "index_ec_stores_on_ozon_client_id", unique: true, where: "(ozon_client_id IS NOT NULL)"
    t.index ["platform"], name: "index_ec_stores_on_platform"
  end

  create_table "ec_suppliers", force: :cascade do |t|
    t.text "address"
    t.string "contact_name"
    t.datetime "created_at", null: false
    t.boolean "is_active", default: true, null: false
    t.text "memo"
    t.string "name", null: false
    t.string "phone"
    t.datetime "updated_at", null: false
    t.string "wechat"
    t.index ["is_active"], name: "index_ec_suppliers_on_is_active"
    t.index ["name"], name: "index_ec_suppliers_on_name", unique: true
  end

  create_table "ec_tool_configurations", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.jsonb "config_json", default: {}, null: false
    t.datetime "created_at", null: false
    t.bigint "created_by_id", null: false
    t.string "name", null: false
    t.bigint "tool_definition_id", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_ec_tool_configurations_on_created_by_id"
    t.index ["tool_definition_id", "active"], name: "idx_ec_tool_configs_definition_active"
    t.index ["tool_definition_id"], name: "index_ec_tool_configurations_on_tool_definition_id"
  end

  create_table "ec_tool_definitions", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.bigint "created_by_id", null: false
    t.string "name", null: false
    t.string "renderer_key", null: false
    t.jsonb "schema_json", default: {}, null: false
    t.string "slug", null: false
    t.string "tool_type", null: false
    t.datetime "updated_at", null: false
    t.integer "version", null: false
    t.index ["created_by_id"], name: "index_ec_tool_definitions_on_created_by_id"
    t.index ["slug"], name: "index_ec_tool_definitions_on_slug", unique: true
    t.index ["tool_type", "active", "version"], name: "idx_ec_tool_definitions_lookup"
    t.index ["tool_type", "version"], name: "index_ec_tool_definitions_on_tool_type_and_version", unique: true
  end

  create_table "ec_weekly_rates", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.decimal "rate_byn_rub", precision: 10, scale: 4, null: false
    t.decimal "rate_cny_rub", precision: 10, scale: 4, null: false
    t.datetime "updated_at", null: false
    t.date "week_start", null: false
    t.index ["week_start"], name: "index_ec_weekly_rates_on_week_start", unique: true
  end

  create_table "feedback_tasks", force: :cascade do |t|
    t.text "assignee_note"
    t.datetime "created_at", null: false
    t.text "description", null: false
    t.jsonb "element_rect", default: {}, null: false
    t.text "element_text"
    t.string "issue_type", null: false
    t.string "page_title"
    t.string "page_url", null: false
    t.integer "scroll_x", default: 0, null: false
    t.integer "scroll_y", default: 0, null: false
    t.string "selector"
    t.string "status", default: "open", null: false
    t.text "suggestion"
    t.datetime "updated_at", null: false
    t.text "user_agent"
    t.bigint "user_id", null: false
    t.integer "viewport_height"
    t.integer "viewport_width"
    t.index ["created_at"], name: "index_feedback_tasks_on_created_at"
    t.index ["status"], name: "index_feedback_tasks_on_status"
    t.index ["user_id"], name: "index_feedback_tasks_on_user_id"
  end

  create_table "messages", force: :cascade do |t|
    t.text "content", null: false
    t.bigint "conversation_id", null: false
    t.datetime "created_at", null: false
    t.string "role", null: false
    t.datetime "updated_at", null: false
    t.jsonb "usage", default: {}, null: false
    t.index ["conversation_id", "created_at"], name: "index_messages_on_conversation_id_and_created_at"
    t.index ["conversation_id"], name: "index_messages_on_conversation_id"
    t.index ["role"], name: "index_messages_on_role"
  end

  create_table "raw_ozon_accrual_by_day", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.date "accrual_date", null: false
    t.string "accrued_category", null: false
    t.decimal "amount", precision: 18, scale: 2, null: false
    t.string "currency_code", default: "RUB", null: false
    t.bigint "ozon_sku_id"
    t.string "posting_number"
    t.datetime "synced_at", null: false
    t.integer "type_id", null: false
    t.string "type_name"
    t.string "unit_number"
    t.index ["account_id", "accrual_date"], name: "idx_ozon_accrual_by_day_account_date"
    t.index ["account_id", "ozon_sku_id"], name: "idx_ozon_accrual_by_day_account_sku"
    t.index ["account_id", "posting_number"], name: "idx_ozon_accrual_by_day_account_posting"
    t.index ["account_id", "type_id"], name: "idx_ozon_accrual_by_day_account_type"
    t.index ["account_id"], name: "index_raw_ozon_accrual_by_day_on_account_id"
  end

  create_table "raw_ozon_analytics", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.integer "adv_view_all"
    t.integer "cancellations"
    t.date "date_from", null: false
    t.date "date_to", null: false
    t.text "dimension_keys", default: [], array: true
    t.jsonb "dimension_values"
    t.integer "hits_tocart"
    t.integer "hits_view_pdp"
    t.integer "ordered_units"
    t.jsonb "raw_json", null: false
    t.integer "returns_count"
    t.decimal "revenue", precision: 18, scale: 2
    t.integer "session_view"
    t.datetime "synced_at"
    t.index ["account_id", "date_from", "date_to"], name: "idx_on_account_id_date_from_date_to_0b8395a459"
    t.index ["account_id"], name: "index_raw_ozon_analytics_on_account_id"
  end

  create_table "raw_ozon_analytics_stocks", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "item_code"
    t.string "item_name"
    t.bigint "ozon_sku"
    t.integer "present", default: 0
    t.jsonb "raw_json", null: false
    t.integer "reserved", default: 0
    t.datetime "synced_at"
    t.string "warehouse_name"
    t.index ["account_id", "ozon_sku"], name: "index_raw_ozon_analytics_stocks_on_account_id_and_ozon_sku"
    t.index ["account_id"], name: "index_raw_ozon_analytics_stocks_on_account_id"
  end

  create_table "raw_ozon_categories", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "category_id", null: false
    t.jsonb "children"
    t.boolean "disabled", default: false
    t.bigint "parent_id"
    t.jsonb "raw_json"
    t.datetime "synced_at"
    t.string "title"
    t.index ["account_id", "category_id"], name: "index_raw_ozon_categories_on_account_id_and_category_id", unique: true
    t.index ["account_id"], name: "index_raw_ozon_categories_on_account_id"
  end

  create_table "raw_ozon_chat_messages", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "chat_id", null: false
    t.datetime "created_at"
    t.jsonb "data"
    t.string "direction"
    t.string "message_id", null: false
    t.jsonb "raw_json", null: false
    t.datetime "synced_at"
    t.index ["account_id", "chat_id"], name: "index_raw_ozon_chat_messages_on_account_id_and_chat_id"
    t.index ["account_id", "message_id"], name: "index_raw_ozon_chat_messages_on_account_id_and_message_id", unique: true
    t.index ["account_id"], name: "index_raw_ozon_chat_messages_on_account_id"
  end

  create_table "raw_ozon_chats", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "chat_id", null: false
    t.string "chat_type"
    t.jsonb "last_message"
    t.string "order_number"
    t.jsonb "raw_json", null: false
    t.string "status"
    t.datetime "synced_at"
    t.integer "unread_count", default: 0
    t.index ["account_id", "chat_id"], name: "index_raw_ozon_chats_on_account_id_and_chat_id", unique: true
    t.index ["account_id", "status"], name: "index_raw_ozon_chats_on_account_id_and_status"
    t.index ["account_id"], name: "index_raw_ozon_chats_on_account_id"
  end

  create_table "raw_ozon_finance_realizations", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.decimal "accruals_for_sale", precision: 18, scale: 2
    t.decimal "close_balance", precision: 18, scale: 2
    t.decimal "compensation_amount", precision: 18, scale: 2
    t.date "doc_date"
    t.string "doc_number"
    t.decimal "money_transfer", precision: 18, scale: 2
    t.jsonb "raw_json", null: false
    t.date "report_date", null: false
    t.jsonb "rows"
    t.decimal "start_balance", precision: 18, scale: 2
    t.datetime "synced_at"
    t.decimal "total_amount", precision: 18, scale: 2
    t.index ["account_id", "report_date"], name: "idx_on_account_id_report_date_933b0d7150", unique: true
    t.index ["account_id"], name: "index_raw_ozon_finance_realizations_on_account_id"
  end

  create_table "raw_ozon_finance_transactions", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.decimal "accruals_for_sale", precision: 18, scale: 2
    t.decimal "amount", precision: 18, scale: 2
    t.string "currency_code", default: "RUB"
    t.decimal "delivery_charge", precision: 18, scale: 2
    t.jsonb "items"
    t.datetime "operation_date"
    t.bigint "operation_id", null: false
    t.string "operation_type"
    t.string "operation_type_name"
    t.datetime "order_date"
    t.string "order_number"
    t.string "posting_number"
    t.jsonb "raw_json", null: false
    t.decimal "return_delivery_charge", precision: 18, scale: 2
    t.decimal "sale_commission", precision: 18, scale: 2
    t.jsonb "services"
    t.datetime "synced_at"
    t.index ["account_id", "operation_date"], name: "idx_on_account_id_operation_date_8317db0aa2"
    t.index ["account_id", "operation_id"], name: "idx_on_account_id_operation_id_5a52bda837", unique: true
    t.index ["account_id", "operation_type"], name: "idx_on_account_id_operation_type_200fccc5ed"
    t.index ["account_id", "posting_number"], name: "idx_on_account_id_posting_number_e34374338f"
    t.index ["account_id"], name: "index_raw_ozon_finance_transactions_on_account_id"
  end

  create_table "raw_ozon_performance_campaign_skus", force: :cascade do |t|
    t.bigint "campaign_id", null: false
    t.datetime "created_at", null: false
    t.string "ozon_sku_id", null: false
    t.datetime "updated_at", null: false
    t.index ["campaign_id", "ozon_sku_id"], name: "idx_ozon_perf_campaign_skus_unique", unique: true
    t.index ["campaign_id"], name: "index_raw_ozon_performance_campaign_skus_on_campaign_id"
  end

  create_table "raw_ozon_performance_campaigns", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "adv_object_type"
    t.string "campaign_id", null: false
    t.datetime "created_at", null: false
    t.decimal "daily_budget", precision: 15, scale: 2
    t.date "from_date"
    t.string "payment_type"
    t.string "placement", default: [], array: true
    t.jsonb "raw_json"
    t.string "state"
    t.datetime "synced_at"
    t.string "title"
    t.date "to_date"
    t.datetime "updated_at", null: false
    t.decimal "weekly_budget", precision: 15, scale: 2
    t.index ["account_id", "campaign_id"], name: "idx_ozon_perf_campaigns_unique", unique: true
    t.index ["account_id"], name: "index_raw_ozon_performance_campaigns_on_account_id"
  end

  create_table "raw_ozon_performance_daily_stats", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "campaign_id", null: false
    t.integer "clicks", default: 0
    t.datetime "created_at", null: false
    t.integer "impressions", default: 0
    t.integer "orders_count", default: 0
    t.decimal "orders_revenue", precision: 15, scale: 2, default: "0.0"
    t.decimal "spend", precision: 15, scale: 2, default: "0.0"
    t.date "stat_date", null: false
    t.datetime "synced_at"
    t.datetime "updated_at", null: false
    t.index ["account_id", "stat_date"], name: "idx_ozon_perf_daily_stats_account_date"
    t.index ["account_id"], name: "index_raw_ozon_performance_daily_stats_on_account_id"
    t.index ["campaign_id", "stat_date"], name: "idx_ozon_perf_daily_stats_unique", unique: true
    t.index ["campaign_id"], name: "index_raw_ozon_performance_daily_stats_on_campaign_id"
  end

  create_table "raw_ozon_performance_sku_spends", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "ad_type", null: false
    t.decimal "allsku_spend", precision: 15, scale: 2
    t.string "campaign_id"
    t.decimal "combo_spend", precision: 15, scale: 2
    t.decimal "cpo_spend", precision: 15, scale: 2
    t.bigint "ozon_sku_id", null: false
    t.date "period_from", null: false
    t.date "period_to", null: false
    t.decimal "spend", precision: 15, scale: 2, null: false
    t.datetime "synced_at", null: false
    t.index ["account_id", "ozon_sku_id"], name: "idx_ozon_perf_sku_spends_sku"
    t.index ["account_id", "period_from", "period_to", "ad_type"], name: "idx_ozon_perf_sku_spends_period"
    t.index ["account_id"], name: "index_raw_ozon_performance_sku_spends_on_account_id"
  end

  create_table "raw_ozon_posting_destinations", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "city"
    t.string "delivery_method_name"
    t.string "delivery_schema"
    t.date "fact_delivery_date"
    t.boolean "is_belarus", default: false, null: false
    t.string "posting_number", null: false
    t.string "region"
    t.datetime "synced_at", null: false
    t.string "warehouse_name"
    t.index ["account_id", "is_belarus"], name: "idx_ozon_posting_dest_belarus"
    t.index ["account_id", "posting_number"], name: "idx_ozon_posting_dest_unique", unique: true
    t.index ["account_id"], name: "index_raw_ozon_posting_destinations_on_account_id"
  end

  create_table "raw_ozon_posting_items", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.decimal "commission_amount", precision: 18, scale: 2
    t.decimal "commission_percent", precision: 5, scale: 2
    t.string "currency_code"
    t.string "name"
    t.string "offer_id"
    t.decimal "old_price", precision: 18, scale: 2
    t.bigint "ozon_sku"
    t.decimal "payout", precision: 18, scale: 2
    t.string "posting_number", null: false
    t.string "posting_type", null: false
    t.decimal "price", precision: 18, scale: 2
    t.integer "quantity", default: 1, null: false
    t.jsonb "raw_json", null: false
    t.datetime "synced_at"
    t.index ["account_id", "offer_id"], name: "index_raw_ozon_posting_items_on_account_id_and_offer_id"
    t.index ["account_id", "ozon_sku"], name: "index_raw_ozon_posting_items_on_account_id_and_ozon_sku"
    t.index ["account_id", "posting_number"], name: "index_raw_ozon_posting_items_on_account_id_and_posting_number"
    t.index ["account_id"], name: "index_raw_ozon_posting_items_on_account_id"
  end

  create_table "raw_ozon_postings_fbo", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.jsonb "additional_data"
    t.jsonb "analytics_data"
    t.integer "cancel_reason_id"
    t.datetime "created_at", null: false
    t.datetime "fact_delivery_date"
    t.jsonb "financial_data"
    t.datetime "in_process_at"
    t.bigint "order_id"
    t.string "order_number"
    t.string "posting_number", null: false
    t.jsonb "raw_json", null: false
    t.string "status", null: false
    t.string "substatus"
    t.datetime "synced_at"
    t.index ["account_id", "created_at"], name: "index_raw_ozon_postings_fbo_on_account_id_and_created_at"
    t.index ["account_id", "posting_number"], name: "index_raw_ozon_postings_fbo_on_account_id_and_posting_number", unique: true
    t.index ["account_id", "status"], name: "index_raw_ozon_postings_fbo_on_account_id_and_status"
    t.index ["account_id"], name: "index_raw_ozon_postings_fbo_on_account_id"
  end

  create_table "raw_ozon_postings_fbs", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "addressee_name"
    t.jsonb "analytics_data"
    t.jsonb "cancellation"
    t.datetime "created_at", null: false
    t.bigint "customer_id"
    t.datetime "delivering_date"
    t.bigint "delivery_method_id"
    t.string "delivery_method_name"
    t.jsonb "financial_data"
    t.datetime "in_process_at"
    t.boolean "is_express", default: false
    t.boolean "is_multibox", default: false
    t.integer "multi_box_qty", default: 1
    t.bigint "order_id"
    t.string "order_number"
    t.string "parent_posting_number"
    t.string "posting_number", null: false
    t.jsonb "raw_json", null: false
    t.jsonb "requirements"
    t.datetime "shipment_date"
    t.datetime "shipment_date_without_delay"
    t.string "status", null: false
    t.string "substatus"
    t.datetime "synced_at"
    t.string "tpl_integration_type"
    t.string "tracking_number"
    t.index ["account_id", "created_at"], name: "index_raw_ozon_postings_fbs_on_account_id_and_created_at"
    t.index ["account_id", "order_id"], name: "index_raw_ozon_postings_fbs_on_account_id_and_order_id"
    t.index ["account_id", "posting_number"], name: "index_raw_ozon_postings_fbs_on_account_id_and_posting_number", unique: true
    t.index ["account_id", "status"], name: "index_raw_ozon_postings_fbs_on_account_id_and_status"
    t.index ["account_id"], name: "index_raw_ozon_postings_fbs_on_account_id"
  end

  create_table "raw_ozon_product_attributes", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "barcode"
    t.jsonb "complex_attributes", default: []
    t.string "offer_id"
    t.bigint "ozon_product_id", null: false
    t.jsonb "product_attributes", default: []
    t.jsonb "raw_json", null: false
    t.datetime "synced_at"
    t.index ["account_id", "ozon_product_id"], name: "idx_on_account_id_ozon_product_id_d42e28fd23", unique: true
    t.index ["account_id"], name: "index_raw_ozon_product_attributes_on_account_id"
  end

  create_table "raw_ozon_product_prices", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.integer "acquiring"
    t.decimal "buybox_price", precision: 18, scale: 2
    t.jsonb "commissions"
    t.string "currency_code"
    t.decimal "discount_percent", precision: 5, scale: 2
    t.boolean "is_in_discount", default: false
    t.decimal "marketing_price", precision: 18, scale: 2
    t.decimal "min_price", precision: 18, scale: 2
    t.string "offer_id"
    t.decimal "old_price", precision: 18, scale: 2
    t.bigint "ozon_product_id", null: false
    t.decimal "price", precision: 18, scale: 2
    t.jsonb "raw_json", null: false
    t.datetime "synced_at"
    t.decimal "volume_weight", precision: 10, scale: 3
    t.index ["account_id", "ozon_product_id"], name: "idx_on_account_id_ozon_product_id_8dec1b4930", unique: true
    t.index ["account_id"], name: "index_raw_ozon_product_prices_on_account_id"
  end

  create_table "raw_ozon_product_queries", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "category"
    t.string "currency"
    t.decimal "gmv", precision: 15, scale: 2
    t.string "name"
    t.string "offer_id"
    t.date "period_from", null: false
    t.date "period_to", null: false
    t.decimal "position", precision: 10, scale: 2
    t.bigint "sku", null: false
    t.datetime "synced_at"
    t.bigint "unique_search_users"
    t.bigint "unique_view_users"
    t.decimal "view_conversion", precision: 10, scale: 4
    t.index ["account_id", "period_from", "sku"], name: "idx_ozon_product_queries_unique", unique: true
    t.index ["account_id"], name: "index_raw_ozon_product_queries_on_account_id"
  end

  create_table "raw_ozon_product_query_details", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "currency"
    t.decimal "gmv", precision: 15, scale: 2
    t.bigint "order_count"
    t.date "period_from", null: false
    t.date "period_to", null: false
    t.decimal "position", precision: 10, scale: 2
    t.string "query", null: false
    t.integer "query_index"
    t.bigint "sku", null: false
    t.datetime "synced_at"
    t.bigint "unique_search_users"
    t.bigint "unique_view_users"
    t.decimal "view_conversion", precision: 10, scale: 4
    t.index ["account_id", "period_from", "sku", "query"], name: "idx_ozon_product_query_details_unique", unique: true
    t.index ["account_id"], name: "index_raw_ozon_product_query_details_on_account_id"
  end

  create_table "raw_ozon_product_stocks", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "offer_id"
    t.bigint "ozon_product_id", null: false
    t.integer "present_fbo", default: 0
    t.integer "present_fbs", default: 0
    t.jsonb "raw_json", null: false
    t.integer "reserved_fbo", default: 0
    t.integer "reserved_fbs", default: 0
    t.jsonb "stocks_by_warehouse"
    t.datetime "synced_at"
    t.index ["account_id", "ozon_product_id"], name: "idx_on_account_id_ozon_product_id_f978ccd87a", unique: true
    t.index ["account_id"], name: "index_raw_ozon_product_stocks_on_account_id"
  end

  create_table "raw_ozon_products", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.jsonb "availabilities"
    t.text "barcodes", default: [], array: true
    t.jsonb "color_image"
    t.jsonb "commissions"
    t.datetime "created_at"
    t.string "currency_code"
    t.bigint "description_category_id"
    t.integer "discounted_fbo_stocks", default: 0
    t.boolean "has_discounted_fbo_item", default: false
    t.jsonb "images"
    t.jsonb "images360"
    t.boolean "is_archived", default: false
    t.boolean "is_autoarchived", default: false
    t.string "name"
    t.string "offer_id"
    t.bigint "ozon_product_id", null: false
    t.jsonb "raw_json", null: false
    t.datetime "synced_at"
    t.bigint "type_id"
    t.index ["account_id", "offer_id"], name: "index_raw_ozon_products_on_account_id_and_offer_id"
    t.index ["account_id", "ozon_product_id"], name: "index_raw_ozon_products_on_account_id_and_ozon_product_id", unique: true
    t.index ["account_id"], name: "index_raw_ozon_products_on_account_id"
  end

  create_table "raw_ozon_promotions", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "action_id", null: false
    t.string "action_type"
    t.datetime "date_end"
    t.datetime "date_start"
    t.text "description"
    t.datetime "freeze_date"
    t.boolean "is_participating", default: false
    t.integer "participating_products_count", default: 0
    t.integer "products_count", default: 0
    t.jsonb "raw_json", null: false
    t.datetime "synced_at"
    t.string "title"
    t.index ["account_id", "action_id"], name: "index_raw_ozon_promotions_on_account_id_and_action_id", unique: true
    t.index ["account_id"], name: "index_raw_ozon_promotions_on_account_id"
  end

  create_table "raw_ozon_questions", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.text "answer"
    t.datetime "answer_at"
    t.datetime "created_at"
    t.string "offer_id"
    t.bigint "ozon_sku"
    t.string "product_name"
    t.string "question_id", null: false
    t.jsonb "raw_json", null: false
    t.string "status"
    t.datetime "synced_at"
    t.text "text"
    t.index ["account_id", "ozon_sku"], name: "index_raw_ozon_questions_on_account_id_and_ozon_sku"
    t.index ["account_id", "question_id"], name: "index_raw_ozon_questions_on_account_id_and_question_id", unique: true
    t.index ["account_id", "status"], name: "index_raw_ozon_questions_on_account_id_and_status"
    t.index ["account_id"], name: "index_raw_ozon_questions_on_account_id"
  end

  create_table "raw_ozon_reports", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.datetime "created_at"
    t.text "error"
    t.text "file_url"
    t.jsonb "params"
    t.jsonb "raw_json", null: false
    t.string "report_code", null: false
    t.string "report_type"
    t.string "status"
    t.datetime "synced_at"
    t.index ["account_id", "report_code"], name: "index_raw_ozon_reports_on_account_id_and_report_code", unique: true
    t.index ["account_id", "report_type"], name: "index_raw_ozon_reports_on_account_id_and_report_type"
    t.index ["account_id", "status"], name: "index_raw_ozon_reports_on_account_id_and_status"
    t.index ["account_id"], name: "index_raw_ozon_reports_on_account_id"
  end

  create_table "raw_ozon_returns", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.jsonb "compensation_status"
    t.datetime "final_moment"
    t.string "offer_id"
    t.bigint "order_id"
    t.string "order_number"
    t.bigint "ozon_sku"
    t.jsonb "place"
    t.string "posting_number"
    t.decimal "price", precision: 18, scale: 2
    t.string "product_name"
    t.integer "quantity", default: 1
    t.jsonb "raw_json", null: false
    t.datetime "return_date"
    t.bigint "return_id", null: false
    t.string "return_reason_name"
    t.string "return_schema", null: false
    t.string "return_type"
    t.jsonb "storage"
    t.datetime "synced_at"
    t.jsonb "target_place"
    t.datetime "visual_change_moment"
    t.string "visual_status"
    t.index ["account_id", "final_moment"], name: "idx_raw_ozon_returns_account_final_moment"
    t.index ["account_id", "posting_number"], name: "index_raw_ozon_returns_on_account_id_and_posting_number"
    t.index ["account_id", "return_date"], name: "idx_raw_ozon_returns_account_return_date"
    t.index ["account_id", "return_id"], name: "index_raw_ozon_returns_on_account_id_and_return_id", unique: true
    t.index ["account_id", "return_schema"], name: "index_raw_ozon_returns_on_account_id_and_return_schema"
    t.index ["account_id", "visual_change_moment"], name: "idx_raw_ozon_returns_account_visual_change_moment"
    t.index ["account_id", "visual_status"], name: "index_raw_ozon_returns_on_account_id_and_visual_status"
    t.index ["account_id"], name: "index_raw_ozon_returns_on_account_id"
  end

  create_table "raw_ozon_reviews", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.text "comment"
    t.datetime "created_at"
    t.jsonb "media"
    t.string "offer_id"
    t.bigint "ozon_sku"
    t.string "product_name"
    t.integer "rating"
    t.jsonb "raw_json", null: false
    t.text "response"
    t.datetime "response_at"
    t.string "response_status"
    t.string "review_id", null: false
    t.string "reviewer_name"
    t.string "status"
    t.datetime "synced_at"
    t.string "title"
    t.datetime "updated_at"
    t.index ["account_id", "ozon_sku"], name: "index_raw_ozon_reviews_on_account_id_and_ozon_sku"
    t.index ["account_id", "rating"], name: "index_raw_ozon_reviews_on_account_id_and_rating"
    t.index ["account_id", "review_id"], name: "index_raw_ozon_reviews_on_account_id_and_review_id", unique: true
    t.index ["account_id", "status"], name: "index_raw_ozon_reviews_on_account_id_and_status"
    t.index ["account_id"], name: "index_raw_ozon_reviews_on_account_id"
  end

  create_table "raw_ozon_seller_accounts", force: :cascade do |t|
    t.text "api_key", null: false
    t.string "client_id", null: false
    t.string "company_name"
    t.string "company_type"
    t.datetime "created_at", null: false
    t.string "inn"
    t.boolean "is_active", default: true, null: false
    t.string "legal_name"
    t.text "memo"
    t.string "ownership_form"
    t.string "performance_client_id"
    t.text "performance_client_secret"
    t.jsonb "raw_json"
    t.datetime "updated_at", null: false
    t.index ["client_id"], name: "index_raw_ozon_seller_accounts_on_client_id", unique: true
  end

  create_table "raw_ozon_supply_orders", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.datetime "created_at"
    t.jsonb "items"
    t.jsonb "raw_json", null: false
    t.string "status"
    t.string "supply_order_id", null: false
    t.datetime "synced_at"
    t.jsonb "timeslot"
    t.index ["account_id", "status"], name: "index_raw_ozon_supply_orders_on_account_id_and_status"
    t.index ["account_id", "supply_order_id"], name: "index_raw_ozon_supply_orders_on_account_id_and_supply_order_id", unique: true
    t.index ["account_id"], name: "index_raw_ozon_supply_orders_on_account_id"
  end

  create_table "raw_ozon_sync_tasks", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.datetime "created_at", null: false
    t.text "error"
    t.datetime "finished_at"
    t.jsonb "results"
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.string "sync_type", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "status"], name: "index_raw_ozon_sync_tasks_on_account_id_and_status"
    t.index ["account_id", "sync_type"], name: "index_raw_ozon_sync_tasks_on_account_id_and_sync_type"
    t.index ["account_id"], name: "index_raw_ozon_sync_tasks_on_account_id"
  end

  create_table "raw_ozon_warehouses", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.boolean "has_entrusted_acceptance", default: false
    t.boolean "is_rfbs", default: false
    t.string "name"
    t.jsonb "raw_json"
    t.string "status"
    t.datetime "synced_at"
    t.bigint "warehouse_id", null: false
    t.index ["account_id", "warehouse_id"], name: "index_raw_ozon_warehouses_on_account_id_and_warehouse_id", unique: true
    t.index ["account_id"], name: "index_raw_ozon_warehouses_on_account_id"
  end

  create_table "raw_wb_account_balances", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "currency", default: "RUB"
    t.decimal "current", precision: 15, scale: 2
    t.decimal "for_withdraw", precision: 15, scale: 2
    t.datetime "snapshot_at", default: -> { "CURRENT_TIMESTAMP" }
    t.index ["account_id"], name: "index_raw_wb_account_balances_on_account_id"
  end

  create_table "raw_wb_ad_campaign_products", id: false, force: :cascade do |t|
    t.decimal "bid", precision: 10, scale: 2
    t.bigint "campaign_id", null: false
    t.bigint "nm_id", null: false
    t.index ["campaign_id", "nm_id"], name: "index_raw_wb_ad_campaign_products_on_campaign_id_and_nm_id", unique: true
    t.index ["campaign_id"], name: "index_raw_wb_ad_campaign_products_on_campaign_id"
  end

  create_table "raw_wb_ad_campaigns", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.integer "campaign_type"
    t.datetime "created_at", null: false
    t.decimal "daily_budget", precision: 15, scale: 2
    t.datetime "end_time"
    t.string "name"
    t.datetime "start_time"
    t.integer "status"
    t.datetime "synced_at"
    t.decimal "total_budget", precision: 15, scale: 2
    t.datetime "updated_at", null: false
    t.bigint "wb_advert_id"
    t.index ["account_id"], name: "index_raw_wb_ad_campaigns_on_account_id"
    t.index ["wb_advert_id"], name: "index_raw_wb_ad_campaigns_on_wb_advert_id", unique: true
  end

  create_table "raw_wb_ad_daily_stats", force: :cascade do |t|
    t.bigint "add_to_cart", default: 0
    t.bigint "campaign_id", null: false
    t.bigint "clicks", default: 0
    t.decimal "cpc", precision: 10, scale: 2
    t.decimal "cr", precision: 10, scale: 4
    t.decimal "ctr", precision: 10, scale: 4
    t.bigint "orders", default: 0
    t.decimal "revenue", precision: 15, scale: 2
    t.decimal "spend", precision: 15, scale: 2
    t.date "stat_date"
    t.bigint "views", default: 0
    t.index ["campaign_id", "stat_date"], name: "index_raw_wb_ad_daily_stats_on_campaign_id_and_stat_date", unique: true
    t.index ["campaign_id"], name: "index_raw_wb_ad_daily_stats_on_campaign_id"
  end

  create_table "raw_wb_ad_keyword_bids", force: :cascade do |t|
    t.decimal "bid", precision: 10, scale: 2
    t.bigint "campaign_id", null: false
    t.boolean "is_active", default: true
    t.string "keyword"
    t.index ["campaign_id"], name: "index_raw_wb_ad_keyword_bids_on_campaign_id"
  end

  create_table "raw_wb_ad_negative_keywords", force: :cascade do |t|
    t.bigint "campaign_id", null: false
    t.string "keyword"
    t.index ["campaign_id"], name: "index_raw_wb_ad_negative_keywords_on_campaign_id"
  end

  create_table "raw_wb_ad_settled_fees", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "advert_id", null: false
    t.string "camp_name"
    t.datetime "created_at", null: false
    t.string "payment_type"
    t.date "period_from", null: false
    t.date "period_to", null: false
    t.datetime "synced_at"
    t.decimal "upd_sum_rub", precision: 15, scale: 4, default: "0.0"
    t.datetime "updated_at", null: false
    t.index ["account_id", "advert_id", "period_from", "period_to"], name: "idx_raw_wb_ad_settled_fees_unique", unique: true
    t.index ["account_id", "period_from"], name: "idx_raw_wb_ad_settled_fees_account_date"
  end

  create_table "raw_wb_ad_sku_spends", force: :cascade do |t|
    t.bigint "campaign_id", null: false
    t.datetime "created_at", null: false
    t.bigint "nm_id", null: false
    t.decimal "spend", precision: 15, scale: 4, default: "0.0"
    t.date "stat_date", null: false
    t.datetime "synced_at"
    t.datetime "updated_at", null: false
    t.index ["campaign_id", "nm_id", "stat_date"], name: "idx_raw_wb_ad_sku_spends_unique", unique: true
    t.index ["nm_id", "stat_date"], name: "index_raw_wb_ad_sku_spends_on_nm_id_and_stat_date"
  end

  create_table "raw_wb_analytics_sales_funnels", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "add_to_cart", default: 0
    t.bigint "add_to_wishlist", default: 0
    t.decimal "avg_orders_per_day", precision: 10, scale: 2
    t.decimal "avg_price", precision: 10, scale: 2
    t.string "brand"
    t.decimal "buyout_percent", precision: 10, scale: 2
    t.bigint "buyouts", default: 0
    t.decimal "buyouts_sum", precision: 15, scale: 2
    t.bigint "cancel_count", default: 0
    t.decimal "cancel_sum", precision: 15, scale: 2
    t.decimal "cart_to_order", precision: 10, scale: 4
    t.decimal "conv_to_cart", precision: 10, scale: 4
    t.decimal "localization_percent", precision: 10, scale: 2
    t.bigint "nm_id"
    t.bigint "open_card", default: 0
    t.bigint "orders", default: 0
    t.decimal "orders_sum", precision: 15, scale: 2
    t.decimal "share_order_percent", precision: 10, scale: 2
    t.date "stat_date", null: false
    t.string "subject"
    t.integer "time_to_ready_days"
    t.integer "time_to_ready_hours"
    t.integer "time_to_ready_mins"
    t.string "vendor_code"
    t.index ["account_id", "stat_date", "nm_id"], name: "idx_on_account_id_stat_date_nm_id_e64f4a1355", unique: true
    t.index ["account_id"], name: "index_raw_wb_analytics_sales_funnels_on_account_id"
  end

  create_table "raw_wb_analytics_search_terms", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "add_to_cart"
    t.integer "add_to_cart_percentile"
    t.decimal "avg_position", precision: 10, scale: 2
    t.string "brand_name"
    t.decimal "cart_to_order", precision: 10, scale: 4
    t.integer "cart_to_order_percentile"
    t.decimal "feedback_rating", precision: 5, scale: 2
    t.bigint "frequency"
    t.string "keyword"
    t.decimal "median_position", precision: 10, scale: 2
    t.bigint "nm_id"
    t.bigint "open_card"
    t.integer "open_card_percentile"
    t.decimal "open_to_cart", precision: 10, scale: 4
    t.integer "open_to_cart_percentile"
    t.bigint "orders", default: 0
    t.integer "orders_percentile"
    t.decimal "price_max", precision: 15, scale: 2
    t.decimal "price_min", precision: 15, scale: 2
    t.string "product_name"
    t.decimal "rating", precision: 5, scale: 2
    t.date "stat_date", null: false
    t.string "subject_name"
    t.string "vendor_code"
    t.integer "visibility"
    t.bigint "week_frequency"
    t.index ["account_id", "stat_date", "keyword", "nm_id"], name: "idx_raw_wb_search_terms_unique", unique: true
    t.index ["account_id"], name: "index_raw_wb_analytics_search_terms_on_account_id"
  end

  create_table "raw_wb_attribute_dicts", force: :cascade do |t|
    t.string "dict_type", null: false
    t.string "name", null: false
    t.string "name_en"
    t.string "wb_id"
    t.index ["dict_type", "wb_id"], name: "index_raw_wb_attribute_dicts_on_dict_type_and_wb_id"
  end

  create_table "raw_wb_categories", force: :cascade do |t|
    t.string "name", null: false
    t.string "name_en"
    t.string "name_zh"
    t.datetime "synced_at"
    t.integer "wb_id", null: false
    t.index ["wb_id"], name: "index_raw_wb_categories_on_wb_id", unique: true
  end

  create_table "raw_wb_characteristics", force: :cascade do |t|
    t.string "data_type"
    t.boolean "is_popular", default: false
    t.boolean "is_required", default: false
    t.integer "max_count", default: 1
    t.string "name", null: false
    t.bigint "subject_id", null: false
    t.datetime "synced_at"
    t.string "unit_name"
    t.integer "wb_id", null: false
    t.index ["subject_id"], name: "index_raw_wb_characteristics_on_subject_id"
    t.index ["wb_id"], name: "index_raw_wb_characteristics_on_wb_id", unique: true
  end

  create_table "raw_wb_chat_messages", force: :cascade do |t|
    t.bigint "chat_id", null: false
    t.string "file_id"
    t.string "sender"
    t.datetime "sent_at", null: false
    t.text "text"
    t.index ["chat_id"], name: "index_raw_wb_chat_messages_on_chat_id"
  end

  create_table "raw_wb_chats", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "buyer_id"
    t.datetime "created_at", null: false
    t.datetime "last_message_at"
    t.bigint "order_id"
    t.datetime "updated_at", null: false
    t.string "wb_chat_id"
    t.index ["account_id"], name: "index_raw_wb_chats_on_account_id"
    t.index ["order_id"], name: "index_raw_wb_chats_on_order_id"
    t.index ["wb_chat_id"], name: "index_raw_wb_chats_on_wb_chat_id", unique: true
  end

  create_table "raw_wb_fbs_stocks", force: :cascade do |t|
    t.integer "account_id", null: false
    t.integer "amount", default: 0, null: false
    t.string "barcode", null: false
    t.datetime "created_at", null: false
    t.bigint "nm_id"
    t.datetime "synced_at"
    t.datetime "updated_at", null: false
    t.index ["account_id", "barcode"], name: "idx_raw_wb_fbs_stocks_unique", unique: true
    t.index ["account_id", "nm_id"], name: "index_raw_wb_fbs_stocks_on_account_id_and_nm_id"
  end

  create_table "raw_wb_finance_details", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.decimal "acquiring_fee", precision: 15, scale: 2
    t.string "barcode"
    t.string "bonus_type_name"
    t.string "brand_name"
    t.decimal "commission_percent", precision: 10, scale: 4
    t.string "country"
    t.datetime "created_at", null: false
    t.decimal "deduction", precision: 15, scale: 2
    t.string "delivery_method"
    t.decimal "delivery_rub", precision: 15, scale: 2
    t.string "doc_type"
    t.decimal "for_pay", precision: 15, scale: 2
    t.bigint "nm_id"
    t.string "office_name"
    t.date "order_dt"
    t.decimal "paid_storage", precision: 15, scale: 2
    t.decimal "penalty", precision: 15, scale: 2
    t.string "ppvz_office_name"
    t.decimal "ppvz_reward", precision: 15, scale: 2
    t.integer "quantity"
    t.decimal "rebill_logistic_cost", precision: 15, scale: 2
    t.integer "report_type"
    t.decimal "retail_amount", precision: 15, scale: 2
    t.decimal "retail_price", precision: 15, scale: 2
    t.decimal "retail_price_with_disc", precision: 15, scale: 2
    t.bigint "rrdid", null: false
    t.string "sa_name"
    t.date "sale_dt"
    t.integer "sale_percent"
    t.string "seller_oper_name", default: "", null: false
    t.bigint "shk_id"
    t.string "srid"
    t.string "subject_name"
    t.datetime "synced_at"
    t.string "ts_name"
    t.datetime "updated_at", null: false
    t.decimal "vw", precision: 15, scale: 2
    t.index ["account_id", "nm_id", "sale_dt"], name: "idx_raw_wb_finance_details_nm_sale"
    t.index ["account_id", "rrdid"], name: "idx_raw_wb_finance_details_unique", unique: true
    t.index ["account_id", "shk_id"], name: "idx_raw_wb_finance_details_shk"
  end

  create_table "raw_wb_goods_returns", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "barcode"
    t.string "brand"
    t.datetime "completed_dt"
    t.string "dst_office_address"
    t.integer "dst_office_id"
    t.datetime "expired_dt"
    t.integer "is_status_active"
    t.bigint "nm_id"
    t.date "order_dt"
    t.bigint "order_id"
    t.datetime "ready_to_return_dt"
    t.string "reason"
    t.string "return_type"
    t.bigint "shk_id", null: false
    t.string "srid"
    t.string "status"
    t.string "sticker_id"
    t.string "subject_name"
    t.datetime "synced_at"
    t.string "tech_size"
    t.index ["account_id", "shk_id"], name: "index_raw_wb_goods_returns_on_account_id_and_shk_id", unique: true
    t.index ["account_id"], name: "index_raw_wb_goods_returns_on_account_id"
    t.index ["nm_id"], name: "index_raw_wb_goods_returns_on_nm_id"
    t.index ["order_id"], name: "index_raw_wb_goods_returns_on_order_id"
  end

  create_table "raw_wb_order_metas", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "meta_type"
    t.bigint "order_id", null: false
    t.datetime "updated_at", null: false
    t.string "value"
    t.index ["order_id"], name: "index_raw_wb_order_metas_on_order_id"
  end

  create_table "raw_wb_order_status_histories", force: :cascade do |t|
    t.datetime "changed_at", default: -> { "CURRENT_TIMESTAMP" }
    t.bigint "order_id", null: false
    t.string "supplier_status"
    t.string "wb_status"
    t.index ["order_id"], name: "index_raw_wb_order_status_histories_on_order_id"
  end

  create_table "raw_wb_orders", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "article"
    t.string "barcode"
    t.jsonb "buyer_info"
    t.bigint "chrt_id"
    t.decimal "converted_price", precision: 15, scale: 2
    t.datetime "created_at", null: false
    t.integer "currency_code", default: 643
    t.string "delivery_type", null: false
    t.string "g_number", limit: 200
    t.boolean "is_zero_order", default: false
    t.bigint "nm_id"
    t.jsonb "optional_meta"
    t.string "order_uid"
    t.decimal "price", precision: 15, scale: 2
    t.jsonb "required_meta"
    t.string "srid"
    t.string "supplier_status"
    t.datetime "synced_at"
    t.datetime "updated_at"
    t.bigint "warehouse_id"
    t.string "warehouse_type"
    t.string "wb_office"
    t.bigint "wb_order_id"
    t.string "wb_status"
    t.index ["account_id"], name: "index_raw_wb_orders_on_account_id"
    t.index ["g_number"], name: "index_raw_wb_orders_on_g_number"
    t.index ["warehouse_id"], name: "index_raw_wb_orders_on_warehouse_id"
    t.index ["wb_order_id"], name: "index_raw_wb_orders_on_wb_order_id", unique: true
  end

  create_table "raw_wb_paid_storages", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.date "calc_date", null: false
    t.datetime "created_at", null: false
    t.bigint "nm_id", null: false
    t.datetime "synced_at"
    t.datetime "updated_at", null: false
    t.string "vendor_code"
    t.decimal "warehouse_price_rub", precision: 15, scale: 4, default: "0.0"
    t.index ["account_id", "calc_date"], name: "idx_raw_wb_paid_storages_account_date"
    t.index ["account_id", "nm_id", "calc_date"], name: "idx_raw_wb_paid_storages_unique", unique: true
  end

  create_table "raw_wb_product_characteristics", force: :cascade do |t|
    t.integer "charc_id"
    t.string "charc_name"
    t.bigint "product_id", null: false
    t.jsonb "value"
    t.index ["product_id"], name: "index_raw_wb_product_characteristics_on_product_id"
  end

  create_table "raw_wb_product_media", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "media_type"
    t.integer "position"
    t.bigint "product_id", null: false
    t.datetime "updated_at", null: false
    t.text "url"
    t.index ["product_id"], name: "index_raw_wb_product_media_on_product_id"
  end

  create_table "raw_wb_product_price_histories", force: :cascade do |t|
    t.datetime "changed_at", default: -> { "CURRENT_TIMESTAMP" }
    t.integer "club_discount"
    t.integer "discount"
    t.decimal "price", precision: 15, scale: 2
    t.bigint "product_id", null: false
    t.index ["product_id"], name: "index_raw_wb_product_price_histories_on_product_id"
  end

  create_table "raw_wb_product_prices", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.integer "club_discount"
    t.datetime "created_at", null: false
    t.integer "discount"
    t.decimal "final_price", precision: 15, scale: 2
    t.boolean "is_in_quarantine", default: false
    t.decimal "price", precision: 15, scale: 2
    t.bigint "product_id", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_raw_wb_product_prices_on_account_id"
    t.index ["product_id"], name: "index_raw_wb_product_prices_on_product_id"
  end

  create_table "raw_wb_product_skus", force: :cascade do |t|
    t.string "barcode"
    t.bigint "chrt_id"
    t.datetime "created_at", null: false
    t.bigint "product_id", null: false
    t.string "skus", default: [], array: true
    t.string "tech_size"
    t.datetime "updated_at", null: false
    t.string "wb_size"
    t.index ["chrt_id"], name: "index_raw_wb_product_skus_on_chrt_id", unique: true
    t.index ["product_id"], name: "index_raw_wb_product_skus_on_product_id"
  end

  create_table "raw_wb_product_tag_links", id: false, force: :cascade do |t|
    t.bigint "product_id", null: false
    t.bigint "tag_id", null: false
    t.index ["product_id", "tag_id"], name: "index_raw_wb_product_tag_links_on_product_id_and_tag_id", unique: true
    t.index ["product_id"], name: "index_raw_wb_product_tag_links_on_product_id"
    t.index ["tag_id"], name: "index_raw_wb_product_tag_links_on_tag_id"
  end

  create_table "raw_wb_product_tags", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "color"
    t.string "name"
    t.integer "wb_tag_id"
    t.index ["account_id"], name: "index_raw_wb_product_tags_on_account_id"
  end

  create_table "raw_wb_products", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "brand"
    t.datetime "created_at", null: false
    t.text "description"
    t.bigint "imt_id"
    t.boolean "is_in_trash", default: false
    t.bigint "nm_id"
    t.bigint "subject_id"
    t.string "subject_name"
    t.datetime "synced_at"
    t.string "title"
    t.datetime "updated_at", null: false
    t.string "vendor_code", null: false
    t.string "wb_category"
    t.index ["account_id"], name: "index_raw_wb_products_on_account_id"
    t.index ["nm_id"], name: "index_raw_wb_products_on_nm_id", unique: true
    t.index ["subject_id"], name: "index_raw_wb_products_on_subject_id"
  end

  create_table "raw_wb_promotion_products", id: false, force: :cascade do |t|
    t.integer "discount"
    t.bigint "nm_id", null: false
    t.bigint "promotion_id", null: false
    t.index ["promotion_id", "nm_id"], name: "index_raw_wb_promotion_products_on_promotion_id_and_nm_id", unique: true
    t.index ["promotion_id"], name: "index_raw_wb_promotion_products_on_promotion_id"
  end

  create_table "raw_wb_promotions", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.integer "discount"
    t.string "name"
    t.datetime "period_end"
    t.datetime "period_start"
    t.datetime "synced_at"
    t.bigint "wb_promotion_id"
    t.index ["account_id"], name: "index_raw_wb_promotions_on_account_id"
    t.index ["wb_promotion_id"], name: "index_raw_wb_promotions_on_wb_promotion_id", unique: true
  end

  create_table "raw_wb_questions", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.datetime "answer_at"
    t.text "answer_text"
    t.boolean "is_answered", default: false
    t.bigint "nm_id"
    t.datetime "synced_at"
    t.text "text"
    t.string "vendor_code"
    t.boolean "was_viewed", default: false
    t.datetime "wb_created_at", null: false
    t.string "wb_question_id"
    t.index ["account_id"], name: "index_raw_wb_questions_on_account_id"
    t.index ["wb_question_id"], name: "index_raw_wb_questions_on_wb_question_id", unique: true
  end

  create_table "raw_wb_return_claims", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "nm_id"
    t.bigint "order_id"
    t.text "reason"
    t.datetime "responded_at"
    t.text "response_text"
    t.string "status"
    t.datetime "synced_at"
    t.string "wb_claim_id"
    t.datetime "wb_created_at", null: false
    t.index ["account_id"], name: "index_raw_wb_return_claims_on_account_id"
    t.index ["order_id"], name: "index_raw_wb_return_claims_on_order_id"
    t.index ["wb_claim_id"], name: "index_raw_wb_return_claims_on_wb_claim_id", unique: true
  end

  create_table "raw_wb_reviews", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.datetime "answer_at"
    t.text "answer_text"
    t.boolean "is_answered", default: false
    t.boolean "is_archived", default: false
    t.boolean "is_pinned", default: false
    t.bigint "nm_id"
    t.jsonb "photo_urls"
    t.integer "rating"
    t.string "size"
    t.datetime "synced_at"
    t.text "text"
    t.string "vendor_code"
    t.jsonb "video_urls"
    t.boolean "was_viewed", default: false
    t.datetime "wb_created_at", null: false
    t.string "wb_review_id"
    t.index ["account_id"], name: "index_raw_wb_reviews_on_account_id"
    t.index ["wb_review_id"], name: "index_raw_wb_reviews_on_wb_review_id", unique: true
  end

  create_table "raw_wb_sales_report_items", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.decimal "additional_payment", precision: 15, scale: 2
    t.string "barcode"
    t.string "brand_name"
    t.decimal "commission_percent", precision: 10, scale: 4
    t.decimal "delivery_rub", precision: 15, scale: 2
    t.string "doc_type"
    t.bigint "nm_id"
    t.datetime "order_dt"
    t.decimal "penalty", precision: 15, scale: 2
    t.decimal "ppvz_for_pay", precision: 15, scale: 2
    t.integer "quantity"
    t.decimal "retail_amount", precision: 15, scale: 2
    t.decimal "retail_price", precision: 15, scale: 2
    t.string "sa_name"
    t.datetime "sale_dt"
    t.integer "sale_percent"
    t.bigint "sales_report_id", null: false
    t.string "srid"
    t.string "subject_name"
    t.string "ts_name"
    t.index ["account_id"], name: "index_raw_wb_sales_report_items_on_account_id"
    t.index ["sales_report_id", "srid", "nm_id", "doc_type"], name: "idx_wb_sales_report_items_unique", unique: true
    t.index ["sales_report_id"], name: "index_raw_wb_sales_report_items_on_sales_report_id"
  end

  create_table "raw_wb_sales_reports", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.date "date_from"
    t.date "date_to"
    t.decimal "net_payable", precision: 15, scale: 2
    t.date "report_created_at"
    t.datetime "synced_at"
    t.decimal "total_commission", precision: 15, scale: 2
    t.decimal "total_delivery", precision: 15, scale: 2
    t.decimal "total_penalty", precision: 15, scale: 2
    t.decimal "total_returns", precision: 15, scale: 2
    t.decimal "total_sales", precision: 15, scale: 2
    t.bigint "wb_report_id"
    t.index ["account_id"], name: "index_raw_wb_sales_reports_on_account_id"
    t.index ["wb_report_id"], name: "index_raw_wb_sales_reports_on_wb_report_id", unique: true
  end

  create_table "raw_wb_seller_accounts", force: :cascade do |t|
    t.text "api_token"
    t.string "company_type"
    t.datetime "created_at", null: false
    t.boolean "is_active", default: true
    t.string "name", null: false
    t.datetime "token_expires_at"
    t.string "token_type"
    t.datetime "updated_at", null: false
  end

  create_table "raw_wb_stats_orders", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "barcode"
    t.string "brand"
    t.datetime "cancel_date"
    t.string "category"
    t.string "country_name"
    t.integer "discount_percent"
    t.decimal "finished_price", precision: 15, scale: 2
    t.string "g_number"
    t.bigint "income_id"
    t.boolean "is_cancel", default: false
    t.boolean "is_realization"
    t.boolean "is_supply"
    t.datetime "last_change_date"
    t.bigint "nm_id"
    t.string "oblast"
    t.string "oblast_okrug_name"
    t.datetime "order_date", null: false
    t.string "order_type"
    t.decimal "price_with_disc", precision: 15, scale: 2
    t.string "region_name"
    t.decimal "spp", precision: 10, scale: 2
    t.string "srid"
    t.string "sticker"
    t.string "subject"
    t.string "supplier_article"
    t.datetime "synced_at"
    t.string "tech_size"
    t.decimal "total_price", precision: 15, scale: 2
    t.string "warehouse_name"
    t.string "warehouse_type"
    t.index ["account_id", "srid"], name: "idx_raw_wb_stats_orders_account_srid", unique: true, where: "(srid IS NOT NULL)"
    t.index ["account_id"], name: "index_raw_wb_stats_orders_on_account_id"
  end

  create_table "raw_wb_stats_sales", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "barcode"
    t.string "brand"
    t.string "category"
    t.integer "discount_percent"
    t.decimal "finished_price", precision: 15, scale: 2
    t.decimal "for_pay", precision: 15, scale: 2
    t.string "g_number"
    t.boolean "is_storno", default: false
    t.datetime "last_change_date"
    t.bigint "nm_id"
    t.decimal "price_with_disc", precision: 15, scale: 2
    t.datetime "sale_date", null: false
    t.string "sale_id"
    t.string "srid"
    t.string "subject"
    t.string "supplier_article"
    t.datetime "synced_at"
    t.string "tech_size"
    t.decimal "total_price", precision: 15, scale: 2
    t.index ["account_id", "sale_id"], name: "index_raw_wb_stats_sales_on_account_id_and_sale_id", unique: true
    t.index ["account_id"], name: "index_raw_wb_stats_sales_on_account_id"
  end

  create_table "raw_wb_stock_histories", force: :cascade do |t|
    t.string "barcode"
    t.integer "quantity"
    t.datetime "snapshot_at", default: -> { "CURRENT_TIMESTAMP" }
    t.bigint "warehouse_id", null: false
    t.index ["warehouse_id"], name: "index_raw_wb_stock_histories_on_warehouse_id"
  end

  create_table "raw_wb_stocks", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "barcode"
    t.integer "quantity", default: 0, null: false
    t.bigint "sku_id"
    t.datetime "updated_at"
    t.bigint "warehouse_id", null: false
    t.index ["account_id", "warehouse_id", "barcode"], name: "idx_raw_wb_stocks_unique", unique: true
    t.index ["account_id"], name: "index_raw_wb_stocks_on_account_id"
    t.index ["sku_id"], name: "index_raw_wb_stocks_on_sku_id"
    t.index ["warehouse_id", "barcode"], name: "index_raw_wb_stocks_on_warehouse_id_and_barcode", unique: true
    t.index ["warehouse_id"], name: "index_raw_wb_stocks_on_warehouse_id"
  end

  create_table "raw_wb_subjects", force: :cascade do |t|
    t.bigint "category_id"
    t.string "name", null: false
    t.string "name_en"
    t.datetime "synced_at"
    t.integer "wb_id", null: false
    t.index ["category_id"], name: "index_raw_wb_subjects_on_category_id"
    t.index ["wb_id"], name: "index_raw_wb_subjects_on_wb_id", unique: true
  end

  create_table "raw_wb_supplies", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.integer "box_type_id"
    t.datetime "closed_at"
    t.datetime "fact_date"
    t.boolean "is_box_on_pallet"
    t.boolean "is_done", default: false
    t.string "name"
    t.bigint "preorder_id"
    t.datetime "scan_dt"
    t.integer "status_id"
    t.datetime "supply_created_at"
    t.datetime "supply_date"
    t.datetime "synced_at"
    t.datetime "updated_at_wb"
    t.string "wb_supply_id"
    t.index ["account_id", "preorder_id"], name: "idx_raw_wb_supplies_account_preorder", unique: true
    t.index ["account_id"], name: "index_raw_wb_supplies_on_account_id"
    t.index ["wb_supply_id"], name: "index_raw_wb_supplies_on_wb_supply_id", unique: true
  end

  create_table "raw_wb_supply_boxes", force: :cascade do |t|
    t.string "barcode"
    t.datetime "created_at", null: false
    t.bigint "supply_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "wb_box_id"
    t.index ["supply_id"], name: "index_raw_wb_supply_boxes_on_supply_id"
  end

  create_table "raw_wb_supply_items", force: :cascade do |t|
    t.integer "accepted_qty", default: 0, null: false
    t.bigint "account_id", null: false
    t.bigint "nm_id", null: false
    t.integer "quantity", default: 0, null: false
    t.datetime "synced_at"
    t.string "wb_supply_id", null: false
    t.index ["account_id", "nm_id"], name: "index_raw_wb_supply_items_on_account_id_and_nm_id"
    t.index ["account_id", "wb_supply_id", "nm_id"], name: "idx_raw_wb_supply_items_unique", unique: true
    t.index ["account_id"], name: "index_raw_wb_supply_items_on_account_id"
  end

  create_table "raw_wb_supply_orders", id: false, force: :cascade do |t|
    t.datetime "added_at", default: -> { "CURRENT_TIMESTAMP" }
    t.bigint "order_id", null: false
    t.bigint "supply_id", null: false
    t.index ["order_id"], name: "index_raw_wb_supply_orders_on_order_id"
    t.index ["supply_id", "order_id"], name: "index_raw_wb_supply_orders_on_supply_id_and_order_id", unique: true
    t.index ["supply_id"], name: "index_raw_wb_supply_orders_on_supply_id"
  end

  create_table "raw_wb_sync_tasks", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.text "file_url"
    t.string "status", default: "pending"
    t.string "task_type"
    t.datetime "updated_at", null: false
    t.string "wb_task_id"
    t.index ["account_id"], name: "index_raw_wb_sync_tasks_on_account_id"
  end

  create_table "raw_wb_warehouses", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.text "address"
    t.string "city"
    t.datetime "created_at", null: false
    t.boolean "is_active", default: true
    t.decimal "latitude", precision: 10, scale: 7
    t.decimal "longitude", precision: 10, scale: 7
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.string "warehouse_type"
    t.bigint "wb_warehouse_id"
    t.string "work_time"
    t.index ["account_id"], name: "index_raw_wb_warehouses_on_account_id"
    t.index ["wb_warehouse_id"], name: "index_raw_wb_warehouses_on_wb_warehouse_id", unique: true
  end

  create_table "roles", force: :cascade do |t|
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_roles_on_code", unique: true
  end

  create_table "skills", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description", null: false
    t.string "name", null: false
    t.text "skill_md", null: false
    t.datetime "updated_at", null: false
    t.string "version", default: "1", null: false
    t.index ["name"], name: "index_skills_on_name", unique: true
  end

  create_table "sub2_user_api_keys", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "encrypted_api_key", null: false
    t.string "name", null: false
    t.string "remote_key_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["remote_key_id"], name: "index_sub2_user_api_keys_on_remote_key_id", unique: true
    t.index ["user_id"], name: "index_sub2_user_api_keys_on_user_id", unique: true
  end

  create_table "user_access_tokens", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "last_used_at"
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["token_digest"], name: "index_user_access_tokens_on_token_digest", unique: true
    t.index ["user_id"], name: "index_user_access_tokens_on_user_id"
  end

  create_table "user_api_keys", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "encrypted_token"
    t.datetime "last_used_at"
    t.string "name", null: false
    t.datetime "revoked_at"
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["revoked_at"], name: "index_user_api_keys_on_revoked_at"
    t.index ["token_digest"], name: "index_user_api_keys_on_token_digest", unique: true
    t.index ["user_id", "name"], name: "index_user_api_keys_on_user_id_and_name", unique: true
    t.index ["user_id"], name: "index_user_api_keys_on_user_id"
  end

  create_table "user_roles", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "role_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["role_id"], name: "index_user_roles_on_role_id"
    t.index ["user_id", "role_id"], name: "index_user_roles_on_user_id_and_role_id", unique: true
    t.index ["user_id"], name: "index_user_roles_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "current_sign_in_at"
    t.string "current_sign_in_ip"
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.datetime "last_sign_in_at"
    t.string "last_sign_in_ip"
    t.string "name"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.integer "sign_in_count", default: 0, null: false
    t.string "time_zone", default: "Asia/Shanghai", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_users_on_active"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "agent_skills", "agents"
  add_foreign_key "agent_skills", "skills"
  add_foreign_key "conversations", "agents"
  add_foreign_key "conversations", "users"
  add_foreign_key "ec_attachment_links", "ec_attachments"
  add_foreign_key "ec_categories", "ec_categories", column: "parent_id"
  add_foreign_key "ec_cost_allocation_items", "ec_cost_allocations", column: "cost_allocation_id"
  add_foreign_key "ec_cost_allocation_items", "ec_sku_batches", column: "sku_batch_id"
  add_foreign_key "ec_master_skus", "ec_categories"
  add_foreign_key "ec_operation_logs", "users", on_delete: :nullify
  add_foreign_key "ec_order_fulfillments", "ec_orders", column: "order_id"
  add_foreign_key "ec_order_fulfillments", "ec_stores", column: "store_id"
  add_foreign_key "ec_order_items", "ec_order_fulfillments", column: "fulfillment_id"
  add_foreign_key "ec_order_items", "ec_orders", column: "order_id"
  add_foreign_key "ec_order_items", "ec_skus", column: "sku_code", primary_key: "sku_code"
  add_foreign_key "ec_order_items", "ec_stores", column: "store_id"
  add_foreign_key "ec_order_source_links", "ec_order_fulfillments", column: "fulfillment_id"
  add_foreign_key "ec_order_source_links", "ec_order_items", column: "item_id"
  add_foreign_key "ec_order_source_links", "ec_orders", column: "order_id"
  add_foreign_key "ec_orders", "ec_stores", column: "store_id"
  add_foreign_key "ec_payment_requests", "ec_purchase_orders", column: "purchase_order_id"
  add_foreign_key "ec_purchase_order_items", "ec_purchase_orders", column: "purchase_order_id"
  add_foreign_key "ec_purchase_order_items", "ec_sku_batches", column: "sku_batch_id"
  add_foreign_key "ec_purchase_order_items", "ec_skus", column: "sku_code", primary_key: "sku_code"
  add_foreign_key "ec_purchase_orders", "ec_suppliers", column: "supplier_id"
  add_foreign_key "ec_sku_batches", "ec_skus", column: "sku_code", primary_key: "sku_code"
  add_foreign_key "ec_sku_categories", "ec_sku_categories", column: "parent_id"
  add_foreign_key "ec_sku_costs", "ec_skus", column: "sku_code", primary_key: "sku_code"
  add_foreign_key "ec_sku_inventory_levels", "ec_stores", column: "store_id"
  add_foreign_key "ec_sku_marketing_states", "ec_skus", column: "sku_id", on_delete: :cascade
  add_foreign_key "ec_sku_marketing_states", "users", column: "changed_by_id", on_delete: :nullify
  add_foreign_key "ec_sku_platform_costs", "ec_skus", column: "sku_code", primary_key: "sku_code"
  add_foreign_key "ec_sku_predicted_costs", "ec_skus", column: "sku_code", primary_key: "sku_code", name: "fk_rails_ec_sku_predicted_costs_sku_code"
  add_foreign_key "ec_sku_product_operators", "ec_sku_products", column: "sku_product_id"
  add_foreign_key "ec_sku_product_operators", "users"
  add_foreign_key "ec_sku_products", "ec_skus", column: "sku_code", primary_key: "sku_code"
  add_foreign_key "ec_sku_products", "ec_stores", column: "store_id"
  add_foreign_key "ec_sku_store_assignments", "ec_skus", column: "sku_code", primary_key: "sku_code"
  add_foreign_key "ec_skus", "ec_master_skus", column: "master_sku_id"
  add_foreign_key "ec_skus", "ec_sku_categories", column: "sku_category_id"
  add_foreign_key "ec_tool_configurations", "ec_tool_definitions", column: "tool_definition_id"
  add_foreign_key "ec_tool_configurations", "users", column: "created_by_id"
  add_foreign_key "ec_tool_definitions", "users", column: "created_by_id"
  add_foreign_key "feedback_tasks", "users"
  add_foreign_key "messages", "conversations"
  add_foreign_key "raw_ozon_accrual_by_day", "raw_ozon_seller_accounts", column: "account_id"
  add_foreign_key "raw_ozon_analytics", "raw_ozon_seller_accounts", column: "account_id"
  add_foreign_key "raw_ozon_analytics_stocks", "raw_ozon_seller_accounts", column: "account_id"
  add_foreign_key "raw_ozon_categories", "raw_ozon_seller_accounts", column: "account_id"
  add_foreign_key "raw_ozon_chat_messages", "raw_ozon_seller_accounts", column: "account_id"
  add_foreign_key "raw_ozon_chats", "raw_ozon_seller_accounts", column: "account_id"
  add_foreign_key "raw_ozon_finance_realizations", "raw_ozon_seller_accounts", column: "account_id"
  add_foreign_key "raw_ozon_finance_transactions", "raw_ozon_seller_accounts", column: "account_id"
  add_foreign_key "raw_ozon_performance_campaign_skus", "raw_ozon_performance_campaigns", column: "campaign_id"
  add_foreign_key "raw_ozon_performance_campaigns", "raw_ozon_seller_accounts", column: "account_id"
  add_foreign_key "raw_ozon_performance_daily_stats", "raw_ozon_performance_campaigns", column: "campaign_id"
  add_foreign_key "raw_ozon_performance_daily_stats", "raw_ozon_seller_accounts", column: "account_id"
  add_foreign_key "raw_ozon_performance_sku_spends", "raw_ozon_seller_accounts", column: "account_id"
  add_foreign_key "raw_ozon_posting_destinations", "raw_ozon_seller_accounts", column: "account_id"
  add_foreign_key "raw_ozon_posting_items", "raw_ozon_seller_accounts", column: "account_id"
  add_foreign_key "raw_ozon_postings_fbo", "raw_ozon_seller_accounts", column: "account_id"
  add_foreign_key "raw_ozon_postings_fbs", "raw_ozon_seller_accounts", column: "account_id"
  add_foreign_key "raw_ozon_product_attributes", "raw_ozon_seller_accounts", column: "account_id"
  add_foreign_key "raw_ozon_product_prices", "raw_ozon_seller_accounts", column: "account_id"
  add_foreign_key "raw_ozon_product_queries", "raw_ozon_seller_accounts", column: "account_id"
  add_foreign_key "raw_ozon_product_query_details", "raw_ozon_seller_accounts", column: "account_id"
  add_foreign_key "raw_ozon_product_stocks", "raw_ozon_seller_accounts", column: "account_id"
  add_foreign_key "raw_ozon_products", "raw_ozon_seller_accounts", column: "account_id"
  add_foreign_key "raw_ozon_promotions", "raw_ozon_seller_accounts", column: "account_id"
  add_foreign_key "raw_ozon_questions", "raw_ozon_seller_accounts", column: "account_id"
  add_foreign_key "raw_ozon_reports", "raw_ozon_seller_accounts", column: "account_id"
  add_foreign_key "raw_ozon_returns", "raw_ozon_seller_accounts", column: "account_id"
  add_foreign_key "raw_ozon_reviews", "raw_ozon_seller_accounts", column: "account_id"
  add_foreign_key "raw_ozon_supply_orders", "raw_ozon_seller_accounts", column: "account_id"
  add_foreign_key "raw_ozon_sync_tasks", "raw_ozon_seller_accounts", column: "account_id"
  add_foreign_key "raw_ozon_warehouses", "raw_ozon_seller_accounts", column: "account_id"
  add_foreign_key "raw_wb_account_balances", "raw_wb_seller_accounts", column: "account_id"
  add_foreign_key "raw_wb_ad_campaign_products", "raw_wb_ad_campaigns", column: "campaign_id"
  add_foreign_key "raw_wb_ad_campaigns", "raw_wb_seller_accounts", column: "account_id"
  add_foreign_key "raw_wb_ad_daily_stats", "raw_wb_ad_campaigns", column: "campaign_id"
  add_foreign_key "raw_wb_ad_keyword_bids", "raw_wb_ad_campaigns", column: "campaign_id"
  add_foreign_key "raw_wb_ad_negative_keywords", "raw_wb_ad_campaigns", column: "campaign_id"
  add_foreign_key "raw_wb_ad_settled_fees", "raw_wb_seller_accounts", column: "account_id"
  add_foreign_key "raw_wb_analytics_sales_funnels", "raw_wb_seller_accounts", column: "account_id"
  add_foreign_key "raw_wb_analytics_search_terms", "raw_wb_seller_accounts", column: "account_id"
  add_foreign_key "raw_wb_characteristics", "raw_wb_subjects", column: "subject_id"
  add_foreign_key "raw_wb_chat_messages", "raw_wb_chats", column: "chat_id"
  add_foreign_key "raw_wb_chats", "raw_wb_orders", column: "order_id"
  add_foreign_key "raw_wb_chats", "raw_wb_seller_accounts", column: "account_id"
  add_foreign_key "raw_wb_finance_details", "raw_wb_seller_accounts", column: "account_id"
  add_foreign_key "raw_wb_goods_returns", "raw_wb_seller_accounts", column: "account_id"
  add_foreign_key "raw_wb_order_metas", "raw_wb_orders", column: "order_id"
  add_foreign_key "raw_wb_order_status_histories", "raw_wb_orders", column: "order_id"
  add_foreign_key "raw_wb_orders", "raw_wb_seller_accounts", column: "account_id"
  add_foreign_key "raw_wb_orders", "raw_wb_warehouses", column: "warehouse_id"
  add_foreign_key "raw_wb_paid_storages", "raw_wb_seller_accounts", column: "account_id"
  add_foreign_key "raw_wb_product_characteristics", "raw_wb_products", column: "product_id"
  add_foreign_key "raw_wb_product_media", "raw_wb_products", column: "product_id"
  add_foreign_key "raw_wb_product_price_histories", "raw_wb_products", column: "product_id"
  add_foreign_key "raw_wb_product_prices", "raw_wb_products", column: "product_id"
  add_foreign_key "raw_wb_product_prices", "raw_wb_seller_accounts", column: "account_id"
  add_foreign_key "raw_wb_product_skus", "raw_wb_products", column: "product_id"
  add_foreign_key "raw_wb_product_tag_links", "raw_wb_product_tags", column: "tag_id"
  add_foreign_key "raw_wb_product_tag_links", "raw_wb_products", column: "product_id"
  add_foreign_key "raw_wb_product_tags", "raw_wb_seller_accounts", column: "account_id"
  add_foreign_key "raw_wb_products", "raw_wb_seller_accounts", column: "account_id"
  add_foreign_key "raw_wb_products", "raw_wb_subjects", column: "subject_id"
  add_foreign_key "raw_wb_promotion_products", "raw_wb_promotions", column: "promotion_id"
  add_foreign_key "raw_wb_promotions", "raw_wb_seller_accounts", column: "account_id"
  add_foreign_key "raw_wb_questions", "raw_wb_seller_accounts", column: "account_id"
  add_foreign_key "raw_wb_return_claims", "raw_wb_orders", column: "order_id"
  add_foreign_key "raw_wb_return_claims", "raw_wb_seller_accounts", column: "account_id"
  add_foreign_key "raw_wb_reviews", "raw_wb_seller_accounts", column: "account_id"
  add_foreign_key "raw_wb_sales_report_items", "raw_wb_sales_reports", column: "sales_report_id"
  add_foreign_key "raw_wb_sales_report_items", "raw_wb_seller_accounts", column: "account_id"
  add_foreign_key "raw_wb_sales_reports", "raw_wb_seller_accounts", column: "account_id"
  add_foreign_key "raw_wb_stats_orders", "raw_wb_seller_accounts", column: "account_id"
  add_foreign_key "raw_wb_stats_sales", "raw_wb_seller_accounts", column: "account_id"
  add_foreign_key "raw_wb_stock_histories", "raw_wb_warehouses", column: "warehouse_id"
  add_foreign_key "raw_wb_stocks", "raw_wb_product_skus", column: "sku_id"
  add_foreign_key "raw_wb_stocks", "raw_wb_seller_accounts", column: "account_id"
  add_foreign_key "raw_wb_stocks", "raw_wb_warehouses", column: "warehouse_id"
  add_foreign_key "raw_wb_subjects", "raw_wb_categories", column: "category_id"
  add_foreign_key "raw_wb_supplies", "raw_wb_seller_accounts", column: "account_id"
  add_foreign_key "raw_wb_supply_boxes", "raw_wb_supplies", column: "supply_id"
  add_foreign_key "raw_wb_supply_items", "raw_wb_seller_accounts", column: "account_id"
  add_foreign_key "raw_wb_supply_orders", "raw_wb_orders", column: "order_id"
  add_foreign_key "raw_wb_supply_orders", "raw_wb_supplies", column: "supply_id"
  add_foreign_key "raw_wb_sync_tasks", "raw_wb_seller_accounts", column: "account_id"
  add_foreign_key "raw_wb_warehouses", "raw_wb_seller_accounts", column: "account_id"
  add_foreign_key "sub2_user_api_keys", "users"
  add_foreign_key "user_access_tokens", "users"
  add_foreign_key "user_api_keys", "users"
  add_foreign_key "user_roles", "roles"
  add_foreign_key "user_roles", "users"
end
