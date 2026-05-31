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

ActiveRecord::Schema[8.0].define(version: 2026_05_31_000008) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "ec_inventory_snapshots", force: :cascade do |t|
    t.string "sku_code", null: false
    t.string "platform", null: false
    t.integer "account_id", null: false
    t.string "store_name"
    t.integer "stock", default: 0, null: false
    t.integer "supply", default: 0, null: false
    t.integer "sold", default: 0, null: false
    t.integer "fbs", default: 0, null: false
    t.datetime "synced_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["sku_code", "platform", "account_id"], name: "idx_ec_inventory_snapshots_unique", unique: true
    t.index ["sku_code"], name: "index_ec_inventory_snapshots_on_sku_code"
  end

  create_table "ec_inventory_totals", force: :cascade do |t|
    t.string "sku_code", null: false
    t.integer "total_received", default: 0, null: false
    t.integer "total_supply", default: 0, null: false
    t.integer "total_stock", default: 0, null: false
    t.integer "total_sold", default: 0, null: false
    t.integer "total_fbs", default: 0, null: false
    t.datetime "synced_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["sku_code"], name: "index_ec_inventory_totals_on_sku_code", unique: true
  end

  create_table "ec_sku_categories", force: :cascade do |t|
    t.string "code", null: false
    t.string "name", null: false
    t.bigint "parent_id"
    t.integer "position", default: 0, null: false
    t.boolean "is_active", default: true, null: false
    t.text "memo"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_ec_sku_categories_on_code", unique: true
    t.index ["is_active"], name: "index_ec_sku_categories_on_is_active"
    t.index ["name"], name: "index_ec_sku_categories_on_name"
    t.index ["parent_id"], name: "index_ec_sku_categories_on_parent_id"
  end

  create_table "ec_operation_tasks", force: :cascade do |t|
    t.string "task_type", null: false
    t.string "status", default: "open", null: false
    t.string "priority", default: "medium", null: false
    t.string "sku_code"
    t.string "platform"
    t.string "store_key"
    t.string "title", null: false
    t.text "reason"
    t.text "suggested_action"
    t.string "owner_name"
    t.date "due_on"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["priority"], name: "index_ec_operation_tasks_on_priority"
    t.index ["sku_code"], name: "index_ec_operation_tasks_on_sku_code"
    t.index ["status"], name: "index_ec_operation_tasks_on_status"
    t.index ["task_type"], name: "index_ec_operation_tasks_on_task_type"
  end

  create_table "ec_cost_allocations", force: :cascade do |t|
    t.string "allocation_no", null: false
    t.string "cost_type", null: false
    t.string "allocation_method", null: false
    t.decimal "total_amount_cny", precision: 12, scale: 4, null: false
    t.date "allocated_on"
    t.string "status", default: "draft", null: false
    t.text "memo"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["allocation_no"], name: "index_ec_cost_allocations_on_allocation_no", unique: true
    t.index ["cost_type"], name: "index_ec_cost_allocations_on_cost_type"
    t.index ["status"], name: "index_ec_cost_allocations_on_status"
  end

  create_table "ec_cost_allocation_items", force: :cascade do |t|
    t.bigint "cost_allocation_id", null: false
    t.bigint "sku_batch_id", null: false
    t.decimal "amount_cny", precision: 12, scale: 4, null: false
    t.text "memo"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["cost_allocation_id", "sku_batch_id"], name: "idx_ec_cost_alloc_items_unique", unique: true
    t.index ["cost_allocation_id"], name: "index_ec_cost_allocation_items_on_cost_allocation_id"
    t.index ["sku_batch_id"], name: "index_ec_cost_allocation_items_on_sku_batch_id"
  end

  create_table "ec_payment_requests", force: :cascade do |t|
    t.bigint "purchase_order_id", null: false
    t.string "payment_type", null: false
    t.decimal "amount_cny", precision: 12, scale: 4, null: false
    t.string "status", default: "pending", null: false
    t.date "requested_on"
    t.datetime "approved_at"
    t.datetime "paid_at"
    t.text "memo"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["payment_type"], name: "index_ec_payment_requests_on_payment_type"
    t.index ["purchase_order_id"], name: "index_ec_payment_requests_on_purchase_order_id"
    t.index ["status"], name: "index_ec_payment_requests_on_status"
  end

  create_table "ec_purchase_order_items", force: :cascade do |t|
    t.bigint "purchase_order_id", null: false
    t.string "sku_code", null: false
    t.bigint "sku_batch_id", null: false
    t.integer "quantity", null: false
    t.decimal "unit_price_cny", precision: 12, scale: 4, null: false
    t.text "memo"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["purchase_order_id", "sku_batch_id"], name: "idx_ec_po_items_order_batch_unique", unique: true
    t.index ["purchase_order_id"], name: "index_ec_purchase_order_items_on_purchase_order_id"
    t.index ["sku_batch_id"], name: "index_ec_purchase_order_items_on_sku_batch_id"
    t.index ["sku_code"], name: "index_ec_purchase_order_items_on_sku_code"
  end

  create_table "ec_purchase_orders", force: :cascade do |t|
    t.string "order_no", null: false
    t.bigint "supplier_id", null: false
    t.date "ordered_on"
    t.string "status", default: "draft", null: false
    t.string "currency", default: "CNY", null: false
    t.text "memo"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["order_no"], name: "index_ec_purchase_orders_on_order_no", unique: true
    t.index ["status"], name: "index_ec_purchase_orders_on_status"
    t.index ["supplier_id"], name: "index_ec_purchase_orders_on_supplier_id"
  end

  create_table "ec_sku_batches", force: :cascade do |t|
    t.string "sku_code", null: false
    t.string "batch_code", null: false
    t.string "status", default: "draft", null: false
    t.integer "purchased_quantity", default: 0, null: false
    t.integer "received_quantity", default: 0, null: false
    t.decimal "purchase_unit_price_cny", precision: 12, scale: 4, default: "0.0", null: false
    t.date "expected_arrival_on"
    t.date "received_on"
    t.text "memo"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["batch_code"], name: "index_ec_sku_batches_on_batch_code", unique: true
    t.index ["sku_code"], name: "index_ec_sku_batches_on_sku_code"
  end

  create_table "ec_sku_costs", force: :cascade do |t|
    t.string "sku_code", null: false
    t.decimal "purchase_price_cny", precision: 10, scale: 4
    t.decimal "freight_to_by_cny", precision: 10, scale: 4
    t.decimal "customs_misc_cny", precision: 10, scale: 4
    t.decimal "customs_duty_rate", precision: 6, scale: 4, default: "0.1"
    t.decimal "import_vat_rate", precision: 6, scale: 4, default: "0.2"
    t.decimal "pkg_length_cm", precision: 8, scale: 2
    t.decimal "pkg_width_cm", precision: 8, scale: 2
    t.decimal "pkg_height_cm", precision: 8, scale: 2
    t.decimal "damage_rate", precision: 6, scale: 4, default: "0.0"
    t.decimal "misc_cost_cny", precision: 10, scale: 4, default: "0.0"
    t.text "memo"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "pkg_volume_override_l", precision: 8, scale: 4
    t.index ["sku_code"], name: "idx_ec_sku_costs_sku_code", unique: true
  end

  create_table "ec_sku_platform_costs", force: :cascade do |t|
    t.string "sku_code", null: false
    t.string "platform", null: false
    t.string "delivery_mode", null: false
    t.string "company_type", null: false
    t.decimal "logistics_coeff", precision: 6, scale: 4
    t.decimal "fbo_delivery_cny", precision: 10, scale: 4, default: "0.0"
    t.decimal "return_rate", precision: 6, scale: 4
    t.decimal "storage_30d_cny", precision: 10, scale: 4, default: "0.0"
    t.decimal "acquiring_rate", precision: 6, scale: 4
    t.decimal "commission_rate", precision: 6, scale: 4
    t.decimal "ad_spend_rate", precision: 6, scale: 4
    t.decimal "sales_tax_rate", precision: 6, scale: 4
    t.decimal "exchange_rate_rub_cny", precision: 8, scale: 4
    t.decimal "target_price_rub", precision: 12, scale: 2
    t.decimal "min_price_rub", precision: 12, scale: 2
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "wb_logistics_base_rub", precision: 8, scale: 2
    t.decimal "ozon_fwd_base_rub", precision: 8, scale: 2
    t.decimal "ozon_fwd_per_liter_rub", precision: 8, scale: 2
    t.decimal "ozon_ret_base_rub", precision: 8, scale: 2
    t.decimal "ozon_ret_per_liter_rub", precision: 8, scale: 2
    t.decimal "ozon_warehouse_op_rub", precision: 8, scale: 2
    t.decimal "ozon_fbs_delivery_rub", precision: 8, scale: 2
    t.decimal "target_price_rf_rub", precision: 12, scale: 2
    t.decimal "target_price_by_rub", precision: 12, scale: 2
    t.decimal "wb_return_rate", precision: 8, scale: 6
    t.decimal "wb_fixed_return_rate", precision: 8, scale: 6
    t.index ["sku_code", "platform", "delivery_mode", "company_type"], name: "idx_ec_sku_platform_costs_unique", unique: true
  end

  create_table "ec_sku_store_assignments", force: :cascade do |t|
    t.string "sku_code", null: false
    t.string "store_key", null: false
    t.string "platform", null: false
    t.string "owner_name"
    t.string "external_id"
    t.date "listed_at"
    t.boolean "is_active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["owner_name"], name: "idx_ec_sku_store_assignments_owner"
    t.index ["sku_code", "store_key"], name: "idx_ec_sku_store_assignments_unique", unique: true
    t.index ["store_key"], name: "idx_ec_sku_store_assignments_store_key"
  end

  create_table "ec_skus", force: :cascade do |t|
    t.string "sku_code", null: false
    t.string "product_name"
    t.boolean "is_active", default: true, null: false
    t.string "owner_name"
    t.text "memo"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "product_name_ru"
    t.bigint "sku_category_id"
    t.string "color"
    t.string "spec"
    t.string "size"
    t.decimal "weight_kg", precision: 10, scale: 4
    t.decimal "volume_l", precision: 10, scale: 4
    t.string "model"
    t.string "quality_grade"
    t.text "features"
    t.index ["is_active"], name: "idx_ec_skus_is_active"
    t.index ["sku_category_id"], name: "index_ec_skus_on_sku_category_id"
    t.index ["sku_code"], name: "idx_ec_skus_sku_code", unique: true
  end

  create_table "ec_stores", force: :cascade do |t|
    t.string "platform", null: false
    t.string "store_name", null: false
    t.string "company_type"
    t.boolean "is_active", default: true, null: false
    t.text "memo"
    t.text "wb_api_token"
    t.integer "wb_raw_account_id"
    t.string "ozon_client_id"
    t.text "ozon_api_key"
    t.string "ozon_performance_client_id"
    t.text "ozon_performance_client_secret"
    t.integer "ozon_raw_account_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ozon_client_id"], name: "index_ec_stores_on_ozon_client_id", unique: true, where: "(ozon_client_id IS NOT NULL)"
    t.index ["platform"], name: "index_ec_stores_on_platform"
  end

  create_table "ec_suppliers", force: :cascade do |t|
    t.string "name", null: false
    t.string "contact_name"
    t.string "phone"
    t.string "wechat"
    t.text "address"
    t.boolean "is_active", default: true, null: false
    t.text "memo"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["is_active"], name: "index_ec_suppliers_on_is_active"
    t.index ["name"], name: "index_ec_suppliers_on_name", unique: true
  end

  create_table "ec_weekly_rates", force: :cascade do |t|
    t.date "week_start", null: false
    t.decimal "rate_cny_rub", precision: 10, scale: 4, null: false
    t.decimal "rate_byn_rub", precision: 10, scale: 4, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["week_start"], name: "index_ec_weekly_rates_on_week_start", unique: true
  end

  create_table "raw_ozon_accrual_by_day", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.date "accrual_date", null: false
    t.string "accrued_category", null: false
    t.integer "type_id", null: false
    t.string "type_name"
    t.decimal "amount", precision: 18, scale: 2, null: false
    t.string "currency_code", default: "RUB", null: false
    t.bigint "ozon_sku_id"
    t.string "posting_number"
    t.string "unit_number"
    t.datetime "synced_at", null: false
    t.index ["account_id", "accrual_date"], name: "idx_ozon_accrual_by_day_account_date"
    t.index ["account_id", "ozon_sku_id"], name: "idx_ozon_accrual_by_day_account_sku"
    t.index ["account_id", "posting_number"], name: "idx_ozon_accrual_by_day_account_posting"
    t.index ["account_id", "type_id"], name: "idx_ozon_accrual_by_day_account_type"
    t.index ["account_id"], name: "index_raw_ozon_accrual_by_day_on_account_id"
  end

  create_table "raw_ozon_analytics", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.date "date_from", null: false
    t.date "date_to", null: false
    t.text "dimension_keys", default: [], array: true
    t.jsonb "dimension_values"
    t.integer "ordered_units"
    t.decimal "revenue", precision: 18, scale: 2
    t.integer "returns_count"
    t.integer "cancellations"
    t.integer "hits_view_pdp"
    t.integer "hits_tocart"
    t.integer "session_view"
    t.integer "adv_view_all"
    t.jsonb "raw_json", null: false
    t.datetime "synced_at"
    t.index ["account_id", "date_from", "date_to"], name: "idx_on_account_id_date_from_date_to_0b8395a459"
    t.index ["account_id"], name: "index_raw_ozon_analytics_on_account_id"
  end

  create_table "raw_ozon_analytics_stocks", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "ozon_sku"
    t.string "item_code"
    t.string "item_name"
    t.string "warehouse_name"
    t.integer "present", default: 0
    t.integer "reserved", default: 0
    t.jsonb "raw_json", null: false
    t.datetime "synced_at"
    t.index ["account_id", "ozon_sku"], name: "index_raw_ozon_analytics_stocks_on_account_id_and_ozon_sku"
    t.index ["account_id"], name: "index_raw_ozon_analytics_stocks_on_account_id"
  end

  create_table "raw_ozon_categories", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "category_id", null: false
    t.bigint "parent_id"
    t.string "title"
    t.boolean "disabled", default: false
    t.jsonb "children"
    t.jsonb "raw_json"
    t.datetime "synced_at"
    t.index ["account_id", "category_id"], name: "index_raw_ozon_categories_on_account_id_and_category_id", unique: true
    t.index ["account_id"], name: "index_raw_ozon_categories_on_account_id"
  end

  create_table "raw_ozon_chat_messages", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "message_id", null: false
    t.string "chat_id", null: false
    t.string "direction"
    t.jsonb "data"
    t.jsonb "raw_json", null: false
    t.datetime "created_at"
    t.datetime "synced_at"
    t.index ["account_id", "chat_id"], name: "index_raw_ozon_chat_messages_on_account_id_and_chat_id"
    t.index ["account_id", "message_id"], name: "index_raw_ozon_chat_messages_on_account_id_and_message_id", unique: true
    t.index ["account_id"], name: "index_raw_ozon_chat_messages_on_account_id"
  end

  create_table "raw_ozon_chats", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "chat_id", null: false
    t.string "chat_type"
    t.string "order_number"
    t.integer "unread_count", default: 0
    t.string "status"
    t.jsonb "last_message"
    t.jsonb "raw_json", null: false
    t.datetime "synced_at"
    t.index ["account_id", "chat_id"], name: "index_raw_ozon_chats_on_account_id_and_chat_id", unique: true
    t.index ["account_id", "status"], name: "index_raw_ozon_chats_on_account_id_and_status"
    t.index ["account_id"], name: "index_raw_ozon_chats_on_account_id"
  end

  create_table "raw_ozon_finance_realizations", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.date "report_date", null: false
    t.string "doc_number"
    t.date "doc_date"
    t.decimal "accruals_for_sale", precision: 18, scale: 2
    t.decimal "compensation_amount", precision: 18, scale: 2
    t.decimal "money_transfer", precision: 18, scale: 2
    t.decimal "total_amount", precision: 18, scale: 2
    t.decimal "start_balance", precision: 18, scale: 2
    t.decimal "close_balance", precision: 18, scale: 2
    t.jsonb "rows"
    t.jsonb "raw_json", null: false
    t.datetime "synced_at"
    t.index ["account_id", "report_date"], name: "idx_on_account_id_report_date_933b0d7150", unique: true
    t.index ["account_id"], name: "index_raw_ozon_finance_realizations_on_account_id"
  end

  create_table "raw_ozon_finance_transactions", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "operation_id", null: false
    t.string "operation_type"
    t.string "operation_type_name"
    t.string "posting_number"
    t.string "order_number"
    t.decimal "amount", precision: 18, scale: 2
    t.string "currency_code", default: "RUB"
    t.decimal "accruals_for_sale", precision: 18, scale: 2
    t.decimal "sale_commission", precision: 18, scale: 2
    t.decimal "delivery_charge", precision: 18, scale: 2
    t.decimal "return_delivery_charge", precision: 18, scale: 2
    t.jsonb "items"
    t.jsonb "services"
    t.jsonb "raw_json", null: false
    t.datetime "operation_date"
    t.datetime "order_date"
    t.datetime "synced_at"
    t.index ["account_id", "operation_date"], name: "idx_on_account_id_operation_date_8317db0aa2"
    t.index ["account_id", "operation_id"], name: "idx_on_account_id_operation_id_5a52bda837", unique: true
    t.index ["account_id", "operation_type"], name: "idx_on_account_id_operation_type_200fccc5ed"
    t.index ["account_id", "posting_number"], name: "idx_on_account_id_posting_number_e34374338f"
    t.index ["account_id"], name: "index_raw_ozon_finance_transactions_on_account_id"
  end

  create_table "raw_ozon_performance_campaign_skus", force: :cascade do |t|
    t.bigint "campaign_id", null: false
    t.string "ozon_sku_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["campaign_id", "ozon_sku_id"], name: "idx_ozon_perf_campaign_skus_unique", unique: true
    t.index ["campaign_id"], name: "index_raw_ozon_performance_campaign_skus_on_campaign_id"
  end

  create_table "raw_ozon_performance_campaigns", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "campaign_id", null: false
    t.string "title"
    t.string "state"
    t.string "adv_object_type"
    t.string "payment_type"
    t.string "placement", default: [], array: true
    t.date "from_date"
    t.date "to_date"
    t.decimal "daily_budget", precision: 15, scale: 2
    t.decimal "weekly_budget", precision: 15, scale: 2
    t.jsonb "raw_json"
    t.datetime "synced_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "campaign_id"], name: "idx_ozon_perf_campaigns_unique", unique: true
    t.index ["account_id"], name: "index_raw_ozon_performance_campaigns_on_account_id"
  end

  create_table "raw_ozon_performance_daily_stats", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "campaign_id", null: false
    t.date "stat_date", null: false
    t.integer "impressions", default: 0
    t.integer "clicks", default: 0
    t.decimal "spend", precision: 15, scale: 2, default: "0.0"
    t.integer "orders_count", default: 0
    t.decimal "orders_revenue", precision: 15, scale: 2, default: "0.0"
    t.datetime "synced_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "stat_date"], name: "idx_ozon_perf_daily_stats_account_date"
    t.index ["account_id"], name: "index_raw_ozon_performance_daily_stats_on_account_id"
    t.index ["campaign_id", "stat_date"], name: "idx_ozon_perf_daily_stats_unique", unique: true
    t.index ["campaign_id"], name: "index_raw_ozon_performance_daily_stats_on_campaign_id"
  end

  create_table "raw_ozon_performance_sku_spends", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.date "period_from", null: false
    t.date "period_to", null: false
    t.string "ad_type", null: false
    t.string "campaign_id"
    t.bigint "ozon_sku_id", null: false
    t.decimal "spend", precision: 15, scale: 2, null: false
    t.decimal "combo_spend", precision: 15, scale: 2
    t.decimal "cpo_spend", precision: 15, scale: 2
    t.datetime "synced_at", null: false
    t.decimal "allsku_spend", precision: 15, scale: 2
    t.index ["account_id", "ozon_sku_id"], name: "idx_ozon_perf_sku_spends_sku"
    t.index ["account_id", "period_from", "period_to", "ad_type"], name: "idx_ozon_perf_sku_spends_period"
    t.index ["account_id"], name: "index_raw_ozon_performance_sku_spends_on_account_id"
  end

  create_table "raw_ozon_posting_destinations", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "posting_number", null: false
    t.string "delivery_schema"
    t.string "city"
    t.string "region"
    t.string "warehouse_name"
    t.string "delivery_method_name"
    t.boolean "is_belarus", default: false, null: false
    t.datetime "synced_at", null: false
    t.date "fact_delivery_date"
    t.index ["account_id", "is_belarus"], name: "idx_ozon_posting_dest_belarus"
    t.index ["account_id", "posting_number"], name: "idx_ozon_posting_dest_unique", unique: true
    t.index ["account_id"], name: "index_raw_ozon_posting_destinations_on_account_id"
  end

  create_table "raw_ozon_posting_items", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "posting_number", null: false
    t.string "posting_type", null: false
    t.bigint "ozon_sku"
    t.string "offer_id"
    t.string "name"
    t.integer "quantity", default: 1, null: false
    t.decimal "price", precision: 18, scale: 2
    t.decimal "old_price", precision: 18, scale: 2
    t.string "currency_code"
    t.decimal "payout", precision: 18, scale: 2
    t.decimal "commission_amount", precision: 18, scale: 2
    t.decimal "commission_percent", precision: 5, scale: 2
    t.jsonb "raw_json", null: false
    t.datetime "synced_at"
    t.index ["account_id", "offer_id"], name: "index_raw_ozon_posting_items_on_account_id_and_offer_id"
    t.index ["account_id", "ozon_sku"], name: "index_raw_ozon_posting_items_on_account_id_and_ozon_sku"
    t.index ["account_id", "posting_number"], name: "index_raw_ozon_posting_items_on_account_id_and_posting_number"
    t.index ["account_id"], name: "index_raw_ozon_posting_items_on_account_id"
  end

  create_table "raw_ozon_postings_fbo", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "posting_number", null: false
    t.bigint "order_id"
    t.string "order_number"
    t.string "status", null: false
    t.string "substatus"
    t.integer "cancel_reason_id"
    t.jsonb "financial_data"
    t.jsonb "analytics_data"
    t.jsonb "additional_data"
    t.jsonb "raw_json", null: false
    t.datetime "in_process_at"
    t.datetime "fact_delivery_date"
    t.datetime "created_at", null: false
    t.datetime "synced_at"
    t.index ["account_id", "created_at"], name: "index_raw_ozon_postings_fbo_on_account_id_and_created_at"
    t.index ["account_id", "posting_number"], name: "index_raw_ozon_postings_fbo_on_account_id_and_posting_number", unique: true
    t.index ["account_id", "status"], name: "index_raw_ozon_postings_fbo_on_account_id_and_status"
    t.index ["account_id"], name: "index_raw_ozon_postings_fbo_on_account_id"
  end

  create_table "raw_ozon_postings_fbs", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "posting_number", null: false
    t.bigint "order_id"
    t.string "order_number"
    t.string "parent_posting_number"
    t.string "status", null: false
    t.string "substatus"
    t.bigint "delivery_method_id"
    t.string "delivery_method_name"
    t.string "tpl_integration_type"
    t.string "tracking_number"
    t.boolean "is_express", default: false
    t.boolean "is_multibox", default: false
    t.integer "multi_box_qty", default: 1
    t.bigint "customer_id"
    t.string "addressee_name"
    t.jsonb "financial_data"
    t.jsonb "analytics_data"
    t.jsonb "requirements"
    t.jsonb "cancellation"
    t.jsonb "raw_json", null: false
    t.datetime "in_process_at"
    t.datetime "shipment_date"
    t.datetime "shipment_date_without_delay"
    t.datetime "delivering_date"
    t.datetime "created_at", null: false
    t.datetime "synced_at"
    t.index ["account_id", "created_at"], name: "index_raw_ozon_postings_fbs_on_account_id_and_created_at"
    t.index ["account_id", "order_id"], name: "index_raw_ozon_postings_fbs_on_account_id_and_order_id"
    t.index ["account_id", "posting_number"], name: "index_raw_ozon_postings_fbs_on_account_id_and_posting_number", unique: true
    t.index ["account_id", "status"], name: "index_raw_ozon_postings_fbs_on_account_id_and_status"
    t.index ["account_id"], name: "index_raw_ozon_postings_fbs_on_account_id"
  end

  create_table "raw_ozon_product_attributes", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "ozon_product_id", null: false
    t.string "offer_id"
    t.jsonb "attributes", default: []
    t.jsonb "complex_attributes", default: []
    t.string "barcode"
    t.jsonb "raw_json", null: false
    t.datetime "synced_at"
    t.index ["account_id", "ozon_product_id"], name: "idx_on_account_id_ozon_product_id_d42e28fd23", unique: true
    t.index ["account_id"], name: "index_raw_ozon_product_attributes_on_account_id"
  end

  create_table "raw_ozon_product_prices", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "ozon_product_id", null: false
    t.string "offer_id"
    t.decimal "price", precision: 18, scale: 2
    t.decimal "old_price", precision: 18, scale: 2
    t.decimal "marketing_price", precision: 18, scale: 2
    t.decimal "min_price", precision: 18, scale: 2
    t.decimal "buybox_price", precision: 18, scale: 2
    t.string "currency_code"
    t.jsonb "commissions"
    t.boolean "is_in_discount", default: false
    t.decimal "discount_percent", precision: 5, scale: 2
    t.integer "acquiring"
    t.decimal "volume_weight", precision: 10, scale: 3
    t.jsonb "raw_json", null: false
    t.datetime "synced_at"
    t.index ["account_id", "ozon_product_id"], name: "idx_on_account_id_ozon_product_id_8dec1b4930", unique: true
    t.index ["account_id"], name: "index_raw_ozon_product_prices_on_account_id"
  end

  create_table "raw_ozon_product_stocks", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "ozon_product_id", null: false
    t.string "offer_id"
    t.integer "present_fbo", default: 0
    t.integer "reserved_fbo", default: 0
    t.integer "present_fbs", default: 0
    t.integer "reserved_fbs", default: 0
    t.jsonb "stocks_by_warehouse"
    t.jsonb "raw_json", null: false
    t.datetime "synced_at"
    t.index ["account_id", "ozon_product_id"], name: "idx_on_account_id_ozon_product_id_f978ccd87a", unique: true
    t.index ["account_id"], name: "index_raw_ozon_product_stocks_on_account_id"
  end

  create_table "raw_ozon_products", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "ozon_product_id", null: false
    t.string "offer_id"
    t.string "name"
    t.bigint "description_category_id"
    t.bigint "type_id"
    t.string "currency_code"
    t.boolean "is_archived", default: false
    t.boolean "is_autoarchived", default: false
    t.boolean "has_discounted_fbo_item", default: false
    t.integer "discounted_fbo_stocks", default: 0
    t.text "barcodes", default: [], array: true
    t.jsonb "images"
    t.jsonb "images360"
    t.jsonb "color_image"
    t.jsonb "commissions"
    t.jsonb "availabilities"
    t.jsonb "raw_json", null: false
    t.datetime "created_at"
    t.datetime "synced_at"
    t.index ["account_id", "offer_id"], name: "index_raw_ozon_products_on_account_id_and_offer_id"
    t.index ["account_id", "ozon_product_id"], name: "index_raw_ozon_products_on_account_id_and_ozon_product_id", unique: true
    t.index ["account_id"], name: "index_raw_ozon_products_on_account_id"
  end

  create_table "raw_ozon_promotions", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "action_id", null: false
    t.string "title"
    t.string "action_type"
    t.text "description"
    t.boolean "is_participating", default: false
    t.integer "participating_products_count", default: 0
    t.integer "products_count", default: 0
    t.jsonb "raw_json", null: false
    t.datetime "date_start"
    t.datetime "date_end"
    t.datetime "freeze_date"
    t.datetime "synced_at"
    t.index ["account_id", "action_id"], name: "index_raw_ozon_promotions_on_account_id_and_action_id", unique: true
    t.index ["account_id"], name: "index_raw_ozon_promotions_on_account_id"
  end

  create_table "raw_ozon_questions", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "question_id", null: false
    t.bigint "ozon_sku"
    t.string "offer_id"
    t.string "product_name"
    t.text "text"
    t.text "answer"
    t.datetime "answer_at"
    t.string "status"
    t.jsonb "raw_json", null: false
    t.datetime "created_at"
    t.datetime "synced_at"
    t.index ["account_id", "ozon_sku"], name: "index_raw_ozon_questions_on_account_id_and_ozon_sku"
    t.index ["account_id", "question_id"], name: "index_raw_ozon_questions_on_account_id_and_question_id", unique: true
    t.index ["account_id", "status"], name: "index_raw_ozon_questions_on_account_id_and_status"
    t.index ["account_id"], name: "index_raw_ozon_questions_on_account_id"
  end

  create_table "raw_ozon_reports", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "report_code", null: false
    t.string "report_type"
    t.string "status"
    t.text "error"
    t.text "file_url"
    t.jsonb "params"
    t.jsonb "raw_json", null: false
    t.datetime "created_at"
    t.datetime "synced_at"
    t.index ["account_id", "report_code"], name: "index_raw_ozon_reports_on_account_id_and_report_code", unique: true
    t.index ["account_id", "report_type"], name: "index_raw_ozon_reports_on_account_id_and_report_type"
    t.index ["account_id", "status"], name: "index_raw_ozon_reports_on_account_id_and_status"
    t.index ["account_id"], name: "index_raw_ozon_reports_on_account_id"
  end

  create_table "raw_ozon_returns", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "return_id", null: false
    t.string "return_schema", null: false
    t.string "return_type"
    t.string "return_reason_name"
    t.string "posting_number"
    t.bigint "order_id"
    t.string "order_number"
    t.bigint "ozon_sku"
    t.string "offer_id"
    t.string "product_name"
    t.integer "quantity", default: 1
    t.decimal "price", precision: 18, scale: 2
    t.jsonb "place"
    t.jsonb "target_place"
    t.jsonb "storage"
    t.string "visual_status"
    t.jsonb "compensation_status"
    t.jsonb "raw_json", null: false
    t.datetime "synced_at"
    t.index ["account_id", "posting_number"], name: "index_raw_ozon_returns_on_account_id_and_posting_number"
    t.index ["account_id", "return_id"], name: "index_raw_ozon_returns_on_account_id_and_return_id", unique: true
    t.index ["account_id", "return_schema"], name: "index_raw_ozon_returns_on_account_id_and_return_schema"
    t.index ["account_id", "visual_status"], name: "index_raw_ozon_returns_on_account_id_and_visual_status"
    t.index ["account_id"], name: "index_raw_ozon_returns_on_account_id"
  end

  create_table "raw_ozon_reviews", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "review_id", null: false
    t.bigint "ozon_sku"
    t.string "offer_id"
    t.string "product_name"
    t.string "reviewer_name"
    t.integer "rating"
    t.string "title"
    t.text "comment"
    t.text "response"
    t.datetime "response_at"
    t.string "response_status"
    t.string "status"
    t.jsonb "media"
    t.jsonb "raw_json", null: false
    t.datetime "created_at"
    t.datetime "updated_at"
    t.datetime "synced_at"
    t.index ["account_id", "ozon_sku"], name: "index_raw_ozon_reviews_on_account_id_and_ozon_sku"
    t.index ["account_id", "rating"], name: "index_raw_ozon_reviews_on_account_id_and_rating"
    t.index ["account_id", "review_id"], name: "index_raw_ozon_reviews_on_account_id_and_review_id", unique: true
    t.index ["account_id", "status"], name: "index_raw_ozon_reviews_on_account_id_and_status"
    t.index ["account_id"], name: "index_raw_ozon_reviews_on_account_id"
  end

  create_table "raw_ozon_seller_accounts", force: :cascade do |t|
    t.string "client_id", null: false
    t.text "api_key", null: false
    t.string "company_name"
    t.string "legal_name"
    t.string "inn"
    t.string "ownership_form"
    t.boolean "is_active", default: true, null: false
    t.text "memo"
    t.jsonb "raw_json"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "performance_client_id"
    t.text "performance_client_secret"
    t.string "company_type"
    t.index ["client_id"], name: "index_raw_ozon_seller_accounts_on_client_id", unique: true
  end

  create_table "raw_ozon_supply_orders", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "supply_order_id", null: false
    t.string "status"
    t.datetime "created_at"
    t.jsonb "timeslot"
    t.jsonb "items"
    t.jsonb "raw_json", null: false
    t.datetime "synced_at"
    t.index ["account_id", "status"], name: "index_raw_ozon_supply_orders_on_account_id_and_status"
    t.index ["account_id", "supply_order_id"], name: "index_raw_ozon_supply_orders_on_account_id_and_supply_order_id", unique: true
    t.index ["account_id"], name: "index_raw_ozon_supply_orders_on_account_id"
  end

  create_table "raw_ozon_sync_tasks", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "sync_type", null: false
    t.string "status", default: "pending", null: false
    t.jsonb "results"
    t.text "error"
    t.datetime "started_at"
    t.datetime "finished_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "status"], name: "index_raw_ozon_sync_tasks_on_account_id_and_status"
    t.index ["account_id", "sync_type"], name: "index_raw_ozon_sync_tasks_on_account_id_and_sync_type"
    t.index ["account_id"], name: "index_raw_ozon_sync_tasks_on_account_id"
  end

  create_table "raw_ozon_warehouses", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "warehouse_id", null: false
    t.string "name"
    t.boolean "is_rfbs", default: false
    t.boolean "has_entrusted_acceptance", default: false
    t.string "status"
    t.jsonb "raw_json"
    t.datetime "synced_at"
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
    t.bigint "campaign_id", null: false
    t.bigint "nm_id", null: false
    t.decimal "bid", precision: 10, scale: 2
    t.index ["campaign_id", "nm_id"], name: "index_raw_wb_ad_campaign_products_on_campaign_id_and_nm_id", unique: true
    t.index ["campaign_id"], name: "index_raw_wb_ad_campaign_products_on_campaign_id"
  end

  create_table "raw_wb_ad_campaigns", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "wb_advert_id"
    t.string "name"
    t.integer "campaign_type"
    t.integer "status"
    t.decimal "daily_budget", precision: 15, scale: 2
    t.decimal "total_budget", precision: 15, scale: 2
    t.datetime "start_time"
    t.datetime "end_time"
    t.datetime "synced_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_raw_wb_ad_campaigns_on_account_id"
    t.index ["wb_advert_id"], name: "index_raw_wb_ad_campaigns_on_wb_advert_id", unique: true
  end

  create_table "raw_wb_ad_daily_stats", force: :cascade do |t|
    t.bigint "campaign_id", null: false
    t.date "stat_date"
    t.bigint "views", default: 0
    t.bigint "clicks", default: 0
    t.decimal "ctr", precision: 10, scale: 4
    t.decimal "cpc", precision: 10, scale: 2
    t.decimal "spend", precision: 15, scale: 2
    t.bigint "add_to_cart", default: 0
    t.bigint "orders", default: 0
    t.decimal "cr", precision: 10, scale: 4
    t.decimal "revenue", precision: 15, scale: 2
    t.index ["campaign_id", "stat_date"], name: "index_raw_wb_ad_daily_stats_on_campaign_id_and_stat_date", unique: true
    t.index ["campaign_id"], name: "index_raw_wb_ad_daily_stats_on_campaign_id"
  end

  create_table "raw_wb_ad_keyword_bids", force: :cascade do |t|
    t.bigint "campaign_id", null: false
    t.string "keyword"
    t.decimal "bid", precision: 10, scale: 2
    t.boolean "is_active", default: true
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
    t.string "payment_type"
    t.decimal "upd_sum_rub", precision: 15, scale: 4, default: "0.0"
    t.date "period_from", null: false
    t.date "period_to", null: false
    t.datetime "synced_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "advert_id", "period_from", "period_to"], name: "idx_raw_wb_ad_settled_fees_unique", unique: true
    t.index ["account_id", "period_from"], name: "idx_raw_wb_ad_settled_fees_account_date"
  end

  create_table "raw_wb_ad_sku_spends", force: :cascade do |t|
    t.bigint "campaign_id", null: false
    t.bigint "nm_id", null: false
    t.date "stat_date", null: false
    t.decimal "spend", precision: 15, scale: 4, default: "0.0"
    t.datetime "synced_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["campaign_id", "nm_id", "stat_date"], name: "idx_raw_wb_ad_sku_spends_unique", unique: true
    t.index ["nm_id", "stat_date"], name: "index_raw_wb_ad_sku_spends_on_nm_id_and_stat_date"
  end

  create_table "raw_wb_analytics_sales_funnels", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.date "stat_date", null: false
    t.bigint "nm_id"
    t.string "vendor_code"
    t.string "brand"
    t.string "subject"
    t.bigint "open_card", default: 0
    t.bigint "add_to_cart", default: 0
    t.bigint "orders", default: 0
    t.decimal "orders_sum", precision: 15, scale: 2
    t.bigint "buyouts", default: 0
    t.decimal "buyouts_sum", precision: 15, scale: 2
    t.bigint "cancel_count", default: 0
    t.decimal "cancel_sum", precision: 15, scale: 2
    t.decimal "conv_to_cart", precision: 10, scale: 4
    t.decimal "cart_to_order", precision: 10, scale: 4
    t.decimal "avg_price", precision: 10, scale: 2
    t.decimal "avg_orders_per_day", precision: 10, scale: 2
    t.decimal "share_order_percent", precision: 10, scale: 2
    t.bigint "add_to_wishlist", default: 0
    t.decimal "localization_percent", precision: 10, scale: 2
    t.decimal "buyout_percent", precision: 10, scale: 2
    t.integer "time_to_ready_days"
    t.integer "time_to_ready_hours"
    t.integer "time_to_ready_mins"
    t.index ["account_id", "stat_date", "nm_id"], name: "idx_on_account_id_stat_date_nm_id_e64f4a1355", unique: true
    t.index ["account_id"], name: "index_raw_wb_analytics_sales_funnels_on_account_id"
  end

  create_table "raw_wb_analytics_search_terms", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.date "stat_date", null: false
    t.string "keyword"
    t.bigint "nm_id"
    t.bigint "orders", default: 0
    t.decimal "avg_position", precision: 10, scale: 2
    t.bigint "frequency"
    t.index ["account_id", "stat_date", "keyword", "nm_id"], name: "idx_raw_wb_search_terms_unique", unique: true
    t.index ["account_id"], name: "index_raw_wb_analytics_search_terms_on_account_id"
  end

  create_table "raw_wb_attribute_dicts", force: :cascade do |t|
    t.string "dict_type", null: false
    t.string "wb_id"
    t.string "name", null: false
    t.string "name_en"
    t.index ["dict_type", "wb_id"], name: "index_raw_wb_attribute_dicts_on_dict_type_and_wb_id"
  end

  create_table "raw_wb_categories", force: :cascade do |t|
    t.integer "wb_id", null: false
    t.string "name", null: false
    t.string "name_en"
    t.string "name_zh"
    t.datetime "synced_at"
    t.index ["wb_id"], name: "index_raw_wb_categories_on_wb_id", unique: true
  end

  create_table "raw_wb_characteristics", force: :cascade do |t|
    t.integer "wb_id", null: false
    t.bigint "subject_id", null: false
    t.string "name", null: false
    t.string "data_type"
    t.string "unit_name"
    t.integer "max_count", default: 1
    t.boolean "is_required", default: false
    t.boolean "is_popular", default: false
    t.datetime "synced_at"
    t.index ["subject_id"], name: "index_raw_wb_characteristics_on_subject_id"
    t.index ["wb_id"], name: "index_raw_wb_characteristics_on_wb_id", unique: true
  end

  create_table "raw_wb_chat_messages", force: :cascade do |t|
    t.bigint "chat_id", null: false
    t.string "sender"
    t.text "text"
    t.string "file_id"
    t.datetime "sent_at", null: false
    t.index ["chat_id"], name: "index_raw_wb_chat_messages_on_chat_id"
  end

  create_table "raw_wb_chats", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "wb_chat_id"
    t.string "buyer_id"
    t.bigint "order_id"
    t.datetime "last_message_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_raw_wb_chats_on_account_id"
    t.index ["order_id"], name: "index_raw_wb_chats_on_order_id"
    t.index ["wb_chat_id"], name: "index_raw_wb_chats_on_wb_chat_id", unique: true
  end

  create_table "raw_wb_fbs_stocks", force: :cascade do |t|
    t.integer "account_id", null: false
    t.string "barcode", null: false
    t.bigint "nm_id"
    t.integer "amount", default: 0, null: false
    t.datetime "synced_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "barcode"], name: "idx_raw_wb_fbs_stocks_unique", unique: true
    t.index ["account_id", "nm_id"], name: "index_raw_wb_fbs_stocks_on_account_id_and_nm_id"
  end

  create_table "raw_wb_finance_details", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "rrdid", null: false
    t.bigint "nm_id"
    t.bigint "shk_id"
    t.string "sa_name"
    t.string "ts_name"
    t.string "barcode"
    t.string "brand_name"
    t.string "subject_name"
    t.string "seller_oper_name", default: "", null: false
    t.integer "report_type"
    t.decimal "retail_price", precision: 15, scale: 2
    t.decimal "retail_price_with_disc", precision: 15, scale: 2
    t.decimal "retail_amount", precision: 15, scale: 2
    t.integer "sale_percent"
    t.decimal "commission_percent", precision: 10, scale: 4
    t.decimal "for_pay", precision: 15, scale: 2
    t.decimal "acquiring_fee", precision: 15, scale: 2
    t.decimal "delivery_rub", precision: 15, scale: 2
    t.decimal "rebill_logistic_cost", precision: 15, scale: 2
    t.decimal "ppvz_reward", precision: 15, scale: 2
    t.decimal "penalty", precision: 15, scale: 2
    t.decimal "paid_storage", precision: 15, scale: 2
    t.decimal "deduction", precision: 15, scale: 2
    t.integer "quantity"
    t.string "doc_type"
    t.string "srid"
    t.date "order_dt"
    t.date "sale_dt"
    t.datetime "synced_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "vw", precision: 15, scale: 2
    t.string "country"
    t.string "office_name"
    t.string "ppvz_office_name"
    t.string "delivery_method"
    t.string "bonus_type_name"
    t.index ["account_id", "nm_id", "sale_dt"], name: "idx_raw_wb_finance_details_nm_sale"
    t.index ["account_id", "rrdid"], name: "idx_raw_wb_finance_details_unique", unique: true
    t.index ["account_id", "shk_id"], name: "idx_raw_wb_finance_details_shk"
  end

  create_table "raw_wb_order_metas", force: :cascade do |t|
    t.bigint "order_id", null: false
    t.string "meta_type"
    t.string "value"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["order_id"], name: "index_raw_wb_order_metas_on_order_id"
  end

  create_table "raw_wb_order_status_histories", force: :cascade do |t|
    t.bigint "order_id", null: false
    t.string "supplier_status"
    t.string "wb_status"
    t.datetime "changed_at", default: -> { "CURRENT_TIMESTAMP" }
    t.index ["order_id"], name: "index_raw_wb_order_status_histories_on_order_id"
  end

  create_table "raw_wb_orders", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "wb_order_id"
    t.string "order_uid"
    t.string "srid"
    t.string "delivery_type", null: false
    t.bigint "nm_id"
    t.bigint "chrt_id"
    t.string "article"
    t.string "barcode"
    t.string "supplier_status"
    t.string "wb_status"
    t.decimal "price", precision: 15, scale: 2
    t.decimal "converted_price", precision: 15, scale: 2
    t.integer "currency_code", default: 643
    t.bigint "warehouse_id"
    t.string "wb_office"
    t.jsonb "required_meta"
    t.jsonb "optional_meta"
    t.jsonb "buyer_info"
    t.boolean "is_zero_order", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at"
    t.datetime "synced_at"
    t.string "g_number", limit: 200
    t.index ["account_id"], name: "index_raw_wb_orders_on_account_id"
    t.index ["g_number"], name: "index_raw_wb_orders_on_g_number"
    t.index ["warehouse_id"], name: "index_raw_wb_orders_on_warehouse_id"
    t.index ["wb_order_id"], name: "index_raw_wb_orders_on_wb_order_id", unique: true
  end

  create_table "raw_wb_paid_storages", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "nm_id", null: false
    t.string "vendor_code"
    t.decimal "warehouse_price_rub", precision: 15, scale: 4, default: "0.0"
    t.date "calc_date", null: false
    t.datetime "synced_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "calc_date"], name: "idx_raw_wb_paid_storages_account_date"
    t.index ["account_id", "nm_id", "calc_date"], name: "idx_raw_wb_paid_storages_unique", unique: true
  end

  create_table "raw_wb_product_characteristics", force: :cascade do |t|
    t.bigint "product_id", null: false
    t.integer "charc_id"
    t.string "charc_name"
    t.jsonb "value"
    t.index ["product_id"], name: "index_raw_wb_product_characteristics_on_product_id"
  end

  create_table "raw_wb_product_media", force: :cascade do |t|
    t.bigint "product_id", null: false
    t.string "media_type"
    t.text "url"
    t.integer "position"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["product_id"], name: "index_raw_wb_product_media_on_product_id"
  end

  create_table "raw_wb_product_price_histories", force: :cascade do |t|
    t.bigint "product_id", null: false
    t.decimal "price", precision: 15, scale: 2
    t.integer "discount"
    t.integer "club_discount"
    t.datetime "changed_at", default: -> { "CURRENT_TIMESTAMP" }
    t.index ["product_id"], name: "index_raw_wb_product_price_histories_on_product_id"
  end

  create_table "raw_wb_product_prices", force: :cascade do |t|
    t.bigint "product_id", null: false
    t.bigint "account_id", null: false
    t.decimal "price", precision: 15, scale: 2
    t.integer "discount"
    t.integer "club_discount"
    t.decimal "final_price", precision: 15, scale: 2
    t.boolean "is_in_quarantine", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_raw_wb_product_prices_on_account_id"
    t.index ["product_id"], name: "index_raw_wb_product_prices_on_product_id"
  end

  create_table "raw_wb_product_skus", force: :cascade do |t|
    t.bigint "product_id", null: false
    t.bigint "chrt_id"
    t.string "tech_size"
    t.string "wb_size"
    t.string "barcode"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "skus", default: [], array: true
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
    t.integer "wb_tag_id"
    t.string "name"
    t.string "color"
    t.index ["account_id"], name: "index_raw_wb_product_tags_on_account_id"
  end

  create_table "raw_wb_products", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "nm_id"
    t.bigint "imt_id"
    t.string "vendor_code", null: false
    t.string "brand"
    t.string "title"
    t.text "description"
    t.bigint "subject_id"
    t.string "subject_name"
    t.string "wb_category"
    t.boolean "is_in_trash", default: false
    t.datetime "synced_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_raw_wb_products_on_account_id"
    t.index ["nm_id"], name: "index_raw_wb_products_on_nm_id", unique: true
    t.index ["subject_id"], name: "index_raw_wb_products_on_subject_id"
  end

  create_table "raw_wb_promotion_products", id: false, force: :cascade do |t|
    t.bigint "promotion_id", null: false
    t.bigint "nm_id", null: false
    t.integer "discount"
    t.index ["promotion_id", "nm_id"], name: "index_raw_wb_promotion_products_on_promotion_id_and_nm_id", unique: true
    t.index ["promotion_id"], name: "index_raw_wb_promotion_products_on_promotion_id"
  end

  create_table "raw_wb_promotions", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "wb_promotion_id"
    t.string "name"
    t.datetime "period_start"
    t.datetime "period_end"
    t.integer "discount"
    t.datetime "synced_at"
    t.index ["account_id"], name: "index_raw_wb_promotions_on_account_id"
    t.index ["wb_promotion_id"], name: "index_raw_wb_promotions_on_wb_promotion_id", unique: true
  end

  create_table "raw_wb_questions", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "wb_question_id"
    t.bigint "nm_id"
    t.string "vendor_code"
    t.text "text"
    t.boolean "was_viewed", default: false
    t.boolean "is_answered", default: false
    t.text "answer_text"
    t.datetime "answer_at"
    t.datetime "wb_created_at", null: false
    t.datetime "synced_at"
    t.index ["account_id"], name: "index_raw_wb_questions_on_account_id"
    t.index ["wb_question_id"], name: "index_raw_wb_questions_on_wb_question_id", unique: true
  end

  create_table "raw_wb_return_claims", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "wb_claim_id"
    t.bigint "order_id"
    t.bigint "nm_id"
    t.string "status"
    t.text "reason"
    t.text "response_text"
    t.datetime "wb_created_at", null: false
    t.datetime "responded_at"
    t.datetime "synced_at"
    t.index ["account_id"], name: "index_raw_wb_return_claims_on_account_id"
    t.index ["order_id"], name: "index_raw_wb_return_claims_on_order_id"
    t.index ["wb_claim_id"], name: "index_raw_wb_return_claims_on_wb_claim_id", unique: true
  end

  create_table "raw_wb_reviews", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "wb_review_id"
    t.bigint "nm_id"
    t.string "vendor_code"
    t.string "size"
    t.integer "rating"
    t.text "text"
    t.jsonb "photo_urls"
    t.jsonb "video_urls"
    t.boolean "was_viewed", default: false
    t.boolean "is_answered", default: false
    t.text "answer_text"
    t.datetime "answer_at"
    t.boolean "is_pinned", default: false
    t.boolean "is_archived", default: false
    t.datetime "wb_created_at", null: false
    t.datetime "synced_at"
    t.index ["account_id"], name: "index_raw_wb_reviews_on_account_id"
    t.index ["wb_review_id"], name: "index_raw_wb_reviews_on_wb_review_id", unique: true
  end

  create_table "raw_wb_sales_report_items", force: :cascade do |t|
    t.bigint "sales_report_id", null: false
    t.bigint "account_id", null: false
    t.bigint "nm_id"
    t.string "sa_name"
    t.string "ts_name"
    t.string "barcode"
    t.string "brand_name"
    t.string "subject_name"
    t.string "doc_type"
    t.integer "quantity"
    t.decimal "retail_price", precision: 15, scale: 2
    t.decimal "retail_amount", precision: 15, scale: 2
    t.integer "sale_percent"
    t.decimal "commission_percent", precision: 10, scale: 4
    t.decimal "delivery_rub", precision: 15, scale: 2
    t.decimal "penalty", precision: 15, scale: 2
    t.decimal "additional_payment", precision: 15, scale: 2
    t.decimal "ppvz_for_pay", precision: 15, scale: 2
    t.string "srid"
    t.datetime "order_dt"
    t.datetime "sale_dt"
    t.index ["account_id"], name: "index_raw_wb_sales_report_items_on_account_id"
    t.index ["sales_report_id", "srid", "nm_id", "doc_type"], name: "idx_wb_sales_report_items_unique", unique: true
    t.index ["sales_report_id"], name: "index_raw_wb_sales_report_items_on_sales_report_id"
  end

  create_table "raw_wb_sales_reports", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "wb_report_id"
    t.date "date_from"
    t.date "date_to"
    t.date "report_created_at"
    t.decimal "total_sales", precision: 15, scale: 2
    t.decimal "total_returns", precision: 15, scale: 2
    t.decimal "total_commission", precision: 15, scale: 2
    t.decimal "total_delivery", precision: 15, scale: 2
    t.decimal "total_penalty", precision: 15, scale: 2
    t.decimal "net_payable", precision: 15, scale: 2
    t.datetime "synced_at"
    t.index ["account_id"], name: "index_raw_wb_sales_reports_on_account_id"
    t.index ["wb_report_id"], name: "index_raw_wb_sales_reports_on_wb_report_id", unique: true
  end

  create_table "raw_wb_seller_accounts", force: :cascade do |t|
    t.string "name", null: false
    t.text "api_token"
    t.string "token_type"
    t.datetime "token_expires_at"
    t.boolean "is_active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "company_type"
  end

  create_table "raw_wb_stats_orders", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "g_number"
    t.datetime "order_date", null: false
    t.datetime "last_change_date"
    t.string "supplier_article"
    t.string "tech_size"
    t.string "barcode"
    t.decimal "total_price", precision: 15, scale: 2
    t.integer "discount_percent"
    t.string "warehouse_name"
    t.string "oblast"
    t.bigint "nm_id"
    t.string "subject"
    t.string "category"
    t.string "brand"
    t.boolean "is_cancel", default: false
    t.datetime "cancel_date"
    t.string "order_type"
    t.string "srid"
    t.datetime "synced_at"
    t.index ["account_id", "srid"], name: "idx_raw_wb_stats_orders_account_srid", unique: true, where: "(srid IS NOT NULL)"
    t.index ["account_id"], name: "index_raw_wb_stats_orders_on_account_id"
  end

  create_table "raw_wb_stats_sales", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "g_number"
    t.datetime "sale_date", null: false
    t.datetime "last_change_date"
    t.string "supplier_article"
    t.string "tech_size"
    t.string "barcode"
    t.decimal "total_price", precision: 15, scale: 2
    t.integer "discount_percent"
    t.decimal "for_pay", precision: 15, scale: 2
    t.decimal "finished_price", precision: 15, scale: 2
    t.decimal "price_with_disc", precision: 15, scale: 2
    t.bigint "nm_id"
    t.string "subject"
    t.string "category"
    t.string "brand"
    t.boolean "is_storno", default: false
    t.string "srid"
    t.datetime "synced_at"
    t.index ["account_id", "srid"], name: "idx_raw_wb_stats_sales_account_srid", unique: true, where: "(srid IS NOT NULL)"
    t.index ["account_id"], name: "index_raw_wb_stats_sales_on_account_id"
  end

  create_table "raw_wb_stock_histories", force: :cascade do |t|
    t.bigint "warehouse_id", null: false
    t.string "barcode"
    t.integer "quantity"
    t.datetime "snapshot_at", default: -> { "CURRENT_TIMESTAMP" }
    t.index ["warehouse_id"], name: "index_raw_wb_stock_histories_on_warehouse_id"
  end

  create_table "raw_wb_stocks", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "warehouse_id", null: false
    t.bigint "sku_id"
    t.string "barcode"
    t.integer "quantity", default: 0, null: false
    t.datetime "updated_at"
    t.index ["account_id", "warehouse_id", "barcode"], name: "idx_raw_wb_stocks_unique", unique: true
    t.index ["account_id"], name: "index_raw_wb_stocks_on_account_id"
    t.index ["sku_id"], name: "index_raw_wb_stocks_on_sku_id"
    t.index ["warehouse_id", "barcode"], name: "index_raw_wb_stocks_on_warehouse_id_and_barcode", unique: true
    t.index ["warehouse_id"], name: "index_raw_wb_stocks_on_warehouse_id"
  end

  create_table "raw_wb_subjects", force: :cascade do |t|
    t.integer "wb_id", null: false
    t.bigint "category_id"
    t.string "name", null: false
    t.string "name_en"
    t.datetime "synced_at"
    t.index ["category_id"], name: "index_raw_wb_subjects_on_category_id"
    t.index ["wb_id"], name: "index_raw_wb_subjects_on_wb_id", unique: true
  end

  create_table "raw_wb_supplies", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "wb_supply_id"
    t.string "name"
    t.string "supply_type", default: "fbs"
    t.boolean "is_done", default: false
    t.datetime "supply_created_at"
    t.datetime "closed_at"
    t.datetime "scan_dt"
    t.datetime "synced_at"
    t.index ["account_id"], name: "index_raw_wb_supplies_on_account_id"
    t.index ["wb_supply_id"], name: "index_raw_wb_supplies_on_wb_supply_id", unique: true
  end

  create_table "raw_wb_supply_boxes", force: :cascade do |t|
    t.bigint "supply_id", null: false
    t.bigint "wb_box_id"
    t.string "barcode"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["supply_id"], name: "index_raw_wb_supply_boxes_on_supply_id"
  end

  create_table "raw_wb_supply_items", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "wb_supply_id", null: false
    t.bigint "nm_id", null: false
    t.integer "quantity", default: 0, null: false
    t.integer "accepted_qty", default: 0, null: false
    t.datetime "synced_at"
    t.index ["account_id", "nm_id"], name: "index_raw_wb_supply_items_on_account_id_and_nm_id"
    t.index ["account_id", "wb_supply_id", "nm_id"], name: "idx_raw_wb_supply_items_unique", unique: true
    t.index ["account_id"], name: "index_raw_wb_supply_items_on_account_id"
  end

  create_table "raw_wb_supply_orders", id: false, force: :cascade do |t|
    t.bigint "supply_id", null: false
    t.bigint "order_id", null: false
    t.datetime "added_at", default: -> { "CURRENT_TIMESTAMP" }
    t.index ["order_id"], name: "index_raw_wb_supply_orders_on_order_id"
    t.index ["supply_id", "order_id"], name: "index_raw_wb_supply_orders_on_supply_id_and_order_id", unique: true
    t.index ["supply_id"], name: "index_raw_wb_supply_orders_on_supply_id"
  end

  create_table "raw_wb_sync_tasks", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "task_type"
    t.string "wb_task_id"
    t.string "status", default: "pending"
    t.text "file_url"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_raw_wb_sync_tasks_on_account_id"
  end

  create_table "raw_wb_warehouses", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "wb_warehouse_id"
    t.string "name", null: false
    t.text "address"
    t.string "work_time"
    t.string "city"
    t.decimal "longitude", precision: 10, scale: 7
    t.decimal "latitude", precision: 10, scale: 7
    t.string "warehouse_type"
    t.boolean "is_active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_raw_wb_warehouses_on_account_id"
    t.index ["wb_warehouse_id"], name: "index_raw_wb_warehouses_on_wb_warehouse_id", unique: true
  end

  add_foreign_key "ec_sku_batches", "ec_skus", column: "sku_code", primary_key: "sku_code"
  add_foreign_key "ec_sku_costs", "ec_skus", column: "sku_code", primary_key: "sku_code"
  add_foreign_key "ec_sku_platform_costs", "ec_skus", column: "sku_code", primary_key: "sku_code"
  add_foreign_key "ec_sku_store_assignments", "ec_skus", column: "sku_code", primary_key: "sku_code"
  add_foreign_key "ec_sku_categories", "ec_sku_categories", column: "parent_id"
  add_foreign_key "ec_skus", "ec_sku_categories", column: "sku_category_id"
  add_foreign_key "ec_cost_allocation_items", "ec_cost_allocations", column: "cost_allocation_id"
  add_foreign_key "ec_cost_allocation_items", "ec_sku_batches", column: "sku_batch_id"
  add_foreign_key "ec_payment_requests", "ec_purchase_orders", column: "purchase_order_id"
  add_foreign_key "ec_purchase_order_items", "ec_purchase_orders", column: "purchase_order_id"
  add_foreign_key "ec_purchase_order_items", "ec_sku_batches", column: "sku_batch_id"
  add_foreign_key "ec_purchase_order_items", "ec_skus", column: "sku_code", primary_key: "sku_code"
  add_foreign_key "ec_purchase_orders", "ec_suppliers", column: "supplier_id"
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
end
