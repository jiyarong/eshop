require "test_helper"

class ErpAI::V3::SkusControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(4).upcase
    @user = create_user_with_roles("ai-v3-full-context-#{@token.downcase}@example.com", "manager")
    @raw_api_token, = UserApiKey.generate_for!(@user, name: "V3 Full Context")
    @time_zone = Time.find_zone!("Asia/Shanghai")
    @master_sku = Ec::MasterSku.create!(master_sku_code: "V3-SPU-#{@token}")
    @sku = Ec::Sku.create!(
      sku_code: "V3-FULL-#{@token}",
      product_name: "V3 full context",
      master_sku: @master_sku
    )
    @related_sku = Ec::Sku.create!(
      sku_code: "V3-RELATED-#{@token}",
      product_name: "V3 related SKU",
      master_sku: @master_sku
    )
    @marketing_state = @sku.marketing_states.create!(
      grade: "A",
      stage: "grw",
      effective_at: @time_zone.local(2026, 8, 1, 9),
      changed_by: @user
    )
    @wb_account = RawWb::SellerAccount.create!(
      name: "V3 WB #{@token}", api_token: "wb-#{@token}", company_type: :small
    )
    @ozon_account = RawOzon::SellerAccount.create!(
      company_name: "V3 Ozon #{@token}", client_id: "ozon-#{@token}", api_key: "key-#{@token}", company_type: :small
    )
    @wb_store = Ec::Store.create!(
      platform: "wb", store_name: "V3 WB #{@token}", company_type: "small", wb_raw_account_id: @wb_account.id
    )
    @ozon_store = Ec::Store.create!(
      platform: "ozon", store_name: "V3 Ozon #{@token}", company_type: "small", ozon_raw_account_id: @ozon_account.id
    )
    @wb_product = Ec::SkuProduct.create!(
      sku: @sku, store: @wb_store, product_id: "71001", product_name: "WB Listing"
    )
    @ozon_product = Ec::SkuProduct.create!(
      sku: @sku, store: @ozon_store, product_id: "OZ-#{@token}", platform_sku_id: "81001",
      product_name: "Ozon Listing"
    )
    @created_weekly_rates = %w[
      2026-07-13 2026-07-20 2026-07-27 2026-08-03 2026-08-10 2026-08-17
    ].filter_map do |week_start|
      next if Ec::WeeklyRate.exists?(week_start: week_start)

      Ec::WeeklyRate.create!(week_start: week_start, rate_cny_rub: 12.0, rate_byn_rub: 27.0)
    end
  end

  teardown do
    Ec::OperationAction.where(ec_sku_id: @sku&.id).delete_all
    Ec::SkuLifecycleEvent.where(sku_id: @sku&.id).delete_all
    Ec::SkuInventoryLevel.where(sku_code: @sku&.sku_code).delete_all
    Ec::OrderItem.where(store_id: [@wb_store&.id, @ozon_store&.id]).delete_all
    Ec::OrderFulfillment.where(store_id: [@wb_store&.id, @ozon_store&.id]).delete_all
    Ec::Order.where(store_id: [@wb_store&.id, @ozon_store&.id]).delete_all
    Ec::Snapshot.where(sku_id: @sku&.id).delete_all
    RawWb::SalesFunnelDaily.where(account_id: @wb_account&.id).delete_all
    RawOzon::SalesFunnelDaily.where(account_id: @ozon_account&.id).delete_all
    RawOzon::WarehouseCluster.where(account_id: @ozon_account&.id).delete_all
    Ec::WeeklyRate.where(id: @created_weekly_rates&.map(&:id)).delete_all
    Ec::SkuProduct.where(id: [@wb_product&.id, @ozon_product&.id]).delete_all
    Ec::Store.where(id: [@wb_store&.id, @ozon_store&.id]).delete_all
    RawWb::SellerAccount.where(id: @wb_account&.id).delete_all
    RawOzon::SellerAccount.where(id: @ozon_account&.id).delete_all
    Ec::SkuMarketingState.where(id: @marketing_state&.id).delete_all
    Ec::Sku.with_deleted.where(id: @related_sku&.id).delete_all
    Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
    Ec::MasterSku.where(id: @master_sku&.id).delete_all
    UserApiKey.where(user_id: @user&.id).delete_all
    UserRole.where(user_id: @user&.id).delete_all
    User.where(id: @user&.id).delete_all
  end

  test "returns sales funnel using the sku drawer funnel analysis query shape" do
    RawWb::SalesFunnelDaily.create!(
      account: @wb_account, stat_date: Date.new(2026, 8, 4), nm_id: 71_001,
      open_card: 100, add_to_cart: 20, orders: 10, buyouts: 8, cancel_count: 1, synced_at: Time.current
    )
    RawOzon::SalesFunnelDaily.create!(
      account: @ozon_account, stat_date: Date.new(2026, 8, 4), sku: 81_001,
      hits_view: 1_000, hits_view_search: 400, hits_view_pdp: 300,
      hits_tocart: 90, hits_tocart_pdp: 60, ordered_units: 30, delivered_units: 20,
      cancellations: 2, synced_at: Time.current
    )
    wb_order_item = create_order(
      @wb_store, "wb", "71001", "delivered", 6,
      buyer_paid_unit_price: 876.54,
      buyer_currency_code: "RUB",
      buyer_paid_synced_at: @time_zone.local(2026, 8, 5, 13),
      seller_discount_unit_price: 42.63,
      seller_discount_currency_code: "BYN",
      seller_discount_synced_at: @time_zone.local(2026, 8, 5, 14)
    )
    create_order(@ozon_store, "ozon", "81001", "delivered", 14)
    Ec::Snapshot.create!(
      sku: @sku,
      snapshot_type: Ec::InventorySnapshot.snapshot_type,
      snapshot_date: Date.new(2026, 8, 9),
      content: {
        overview: { book_stock: 150 },
        distribution: {
          levels: [
            { store_id: @wb_store.id, fulfillment_type: "fbw", quantity: 45 },
            {
              platform: "ozon", store_id: @ozon_store.id, store_name: @ozon_store.store_name,
              account_id: @ozon_account.id, fulfillment_type: "fbo", quantity: 30
            },
            {
              platform: "ozon", store_id: @ozon_store.id, store_name: @ozon_store.store_name,
              account_id: @ozon_account.id, fulfillment_type: "fbs", quantity: 5
            }
          ]
        }
      }
    )
    Ec::SkuInventoryLevel.create!(
      sku_code: @sku.sku_code,
      platform: "ozon",
      account_id: @ozon_account.id,
      store: @ozon_store,
      store_name: @ozon_store.store_name,
      fulfillment_type: "fbs",
      quantity: 5,
      is_latest: true,
      synced_at: @time_zone.local(2026, 8, 9, 10),
      metadata: { raw_fbs_quantity: 8 }
    )
    first_sale = @sku.lifecycle_events.create!(
      event_type: "first_sale",
      occurred_at: @time_zone.local(2026, 8, 4, 12),
      source_type: "Ec::OrderItem",
      source_id: 1001,
      source_key: "v3:first-sale:#{@token}",
      sku_product: @ozon_product,
      content: {
        order_id: 100,
        order_item_id: 1001,
        platform: "ozon",
        store_id: @ozon_store.id,
        sku_product_id: @ozon_product.id,
        quantity: 1,
        platform_sku_id: @ozon_product.platform_sku_id
      }
    )
    @sku.lifecycle_events.create!(
      event_type: "marketing_state_changed",
      occurred_at: @time_zone.local(2026, 8, 6, 9),
      source_type: "Ec::SkuMarketingState",
      source_id: 1002,
      source_key: "v3:marketing-state:#{@token}",
      content: {
        to_grade: "A",
        to_stage: "grw",
        initial_state: true
      }
    )
    pricing_action = create_operation_action(
      operation_type: "listing_pricing",
      operated_at: @time_zone.local(2026, 8, 4, 11),
      diff_result: { fields: { price: { from: 100, to: 120 } } }
    )
    create_operation_action(
      operation_type: "sku_inbound_change",
      operated_at: @time_zone.local(2026, 8, 5, 11),
      diff_result: { fields: { platform_inbound_quantity: { from: 0, to: 10 } } }
    )

    travel_to Time.utc(2026, 8, 10, 12) do
      get "/ai/v3/sku/full_context",
        params: { sku_code: @sku.sku_code.downcase, period_from: "2026-08-03", period_to: "2026-08-09" },
        headers: bearer_headers
    end

    assert_response :success
    data = response.parsed_body.fetch("data")
    assert_equal 3, data.fetch("schema_version")
    assert_equal @sku.sku_code, data.fetch("sku_code")
    assert_equal({ "from" => "2026-08-03", "to" => "2026-08-09" }, data.fetch("period").slice("from", "to"))

    base = data.fetch("base")
    assert_equal @master_sku.master_sku_code, base.fetch("spu_code")
    assert_equal @master_sku.id, base.fetch("spu_id")
    assert_equal [@related_sku.sku_code], base.fetch("related_spu_sku_codes")
    assert_equal "GRW", base.fetch("current_stage")
    assert_equal "A", base.fetch("current_grade")
    assert_equal(
      [
        {
          "store_id" => @wb_store.id,
          "platform" => "wb",
          "product_id" => @wb_product.product_id,
          "offer_id" => @wb_product.offer_id,
          "product_info" => nil,
          "price_info" => nil
        },
        {
          "store_id" => @ozon_store.id,
          "platform" => "ozon",
          "product_id" => @ozon_product.product_id,
          "offer_id" => @ozon_product.offer_id,
          "product_info" => nil,
          "price_info" => nil
        }
      ],
      base.fetch("sku_products")
    )

    inventory_values = data.dig("inventory", "current_inventory_info", "values")
    assert_equal 5, inventory_values.fetch("platform_fbs_stock")
    assert_equal 8, inventory_values.fetch("platform_reported_fbs_stock")
    history = data.dig("inventory", "history_inventory_info")
    total_trend = history.fetch("sku_inventory_trend")
    assert_equal 8, total_trend.fetch("weeks").size
    assert_includes total_trend.fetch("metrics"), "daily_sales_velocity"
    assert_equal "2026-08-09", total_trend.fetch("weeks").find { |week| week.fetch("week_start") == "2026-08-03" }.fetch("snapshot_date")
    store_trend = history.fetch("store_listing_inventory_trend")
    assert_equal({ "from_date" => "2026-07-14", "to_date" => "2026-08-10" }, store_trend.slice("from_date", "to_date"))
    assert_equal 1, store_trend.fetch("store_listings").size
    assert_equal 28, store_trend.fetch("store_listings").first.fetch("days").size
    assert_equal 5, store_trend.fetch("store_listings").first.fetch("days").find { |day| day.fetch("date") == "2026-08-09" }.dig("values", "fbs_stock")

    lifecycle = data.fetch("lifecycle")
    assert_equal 2, lifecycle.dig("key_events", "events").size
    assert_equal %w[first_sale marketing_state_changed], lifecycle.dig("key_events", "events").map { |event| event.fetch("event_type") }
    assert_equal "2026-08-04", lifecycle.dig("key_events", "events").first.fetch("occurred_on")
    assert_equal "v3:first-sale:#{@token}", lifecycle.dig("key_events", "events").first.fetch("source_key")
    assert_equal first_sale.id, lifecycle.dig("key_events", "events").first.fetch("id")
    assert_includes lifecycle.dig("summary", "fields"), "lifecycle_days"
    assert_equal 7, lifecycle.dig("summary", "values", "lifecycle_days")

    assert_equal [], data.fetch("supply_orders_full_period")
    operation_actions = data.fetch("operation_actions_full_period")
    assert_equal [pricing_action.id], operation_actions.map { |row| row.fetch("action_id") }
    assert_equal ["listing_pricing"], operation_actions.map { |row| row.fetch("operation_type") }
    assert_equal(
      { "from" => 100, "to" => 120 },
      operation_actions.sole.dig("diff_result", "fields", "price")
    )
    assert_equal(
      { "from" => "2026-08-03", "to" => "2026-08-09", "days" => 7, "source" => "ec_orders.ordered_at" },
      data.dig("warehouse_recommendation", "sales_period")
    )
    search_terms = data.fetch("search_terms_per_week")
    assert_equal [{ "period_from" => "2026-08-03", "period_to" => "2026-08-09", "is_partial" => false }],
      search_terms.map { |period| period.slice("period_from", "period_to", "is_partial") }
    assert_equal %w[ozon wb], search_terms.sole.fetch("stores").map { |store| store.fetch("platform") }

    advertising = data.fetch("advertise_per_week")
    assert_equal [{ "period_from" => "2026-08-03", "period_to" => "2026-08-09", "is_partial" => false }],
      advertising.map { |period| period.slice("period_from", "period_to", "is_partial") }
    assert_equal %w[ozon wb], advertising.sole.fetch("stores").map { |store| store.fetch("platform") }

    orders = data.fetch("ec_orders_full_period")
    assert_equal 2, orders.size
    wb_order = orders.find { |row| row.fetch("item_id") == wb_order_item.id }
    assert_equal @sku.sku_code, wb_order.fetch("sku_code")
    assert_equal 876.54, wb_order.fetch("buyer_paid_unit_price")
    assert_equal "RUB", wb_order.fetch("buyer_currency_code")
    assert_equal 42.63, wb_order.fetch("seller_discount_unit_price")
    assert_equal "BYN", wb_order.fetch("seller_discount_currency_code")

    profit = data.fetch("profit")
    profit_overview = profit.fetch("sku_profit_overview_per_week")
    assert_includes profit_overview.fetch("metrics"), "net_sales"
    assert_includes profit_overview.fetch("metrics"), "annualized_net_profit_cny"
    assert_equal %w[P-3 P-2 P-1 P0], profit_overview.fetch("periods").map { |period| period.fetch("period_key") }
    assert_equal %w[P-3 P-2 P-1 P0], profit.fetch("sku_profit_store_listing_perweek").fetch("periods").map { |period| period.fetch("period_key") }

    sales_funnel = data.fetch("sales_funnel")
    assert_not sales_funnel.key?("sales_funnel_per_week")

    overview = sales_funnel.fetch("sku_funnel_overview_per_week")
    assert_equal %w[P-3 P-2 P-1 P0], overview.fetch("periods").map { |period| period.fetch("period_key") }
    selected_period = overview.fetch("periods").last
    assert_equal(
      {
        "product_card_views" => 400,
        "cart_additions" => 80,
        "cart_rate" => 20,
        "orders" => 40,
        "cart_to_order_rate" => 50,
        "cancellations" => 3,
        "conversions" => 20,
        "visit_to_conversion_rate" => 5,
        "net_sales" => 20,
        "sku_ending_inventory" => 150
      },
      selected_period.fetch("values")
    )

    store_listing = sales_funnel.fetch("sku_funnel_store_listing_perweek")
    assert_includes store_listing.fetch("metrics"), "ozon_total_views"
    assert_includes store_listing.fetch("metrics"), "wb_buyout_rate"
    assert_equal %w[P-3 P-2 P-1 P0], store_listing.fetch("periods").map { |period| period.fetch("period_key") }
    assert_equal 2, store_listing.fetch("store_listings").size

    wb_listing = store_listing.fetch("store_listings").find { |listing| listing.fetch("platform") == "wb" }
    assert_equal @wb_product.id, wb_listing.fetch("sku_product_id")
    assert_equal "WB Listing", wb_listing.fetch("listing_label")
    assert_equal 100, wb_listing.fetch("rows_per_week").last.dig("values", "product_card_views")
    assert_equal 6, wb_listing.fetch("rows_per_week").last.dig("values", "net_sales")

    ozon_listing = store_listing.fetch("store_listings").find { |listing| listing.fetch("platform") == "ozon" }
    assert_equal @ozon_product.id, ozon_listing.fetch("sku_product_id")
    assert_equal 1_000, ozon_listing.fetch("rows_per_week").last.dig("values", "ozon_total_views")
    assert_equal 14, ozon_listing.fetch("rows_per_week").last.dig("values", "net_sales")
  end

  test "defaults to the latest completed natural week like the sku drawer sales funnel tab" do
    travel_to Time.utc(2026, 8, 27, 12) do
      get "/ai/v3/sku/full_context",
        params: { sku_code: @sku.sku_code },
        headers: bearer_headers
    end

    assert_response :success
    assert_equal(
      { "from" => "2026-08-17", "to" => "2026-08-23" },
      response.parsed_body.dig("data", "period").slice("from", "to")
    )
  end

  test "returns individual context sections with a common v3 envelope" do
    endpoints = {
      "/ai/v3/sku/base_context" => "base",
      "/ai/v3/sku/sales_funnel_context" => "sales_funnel",
      "/ai/v3/sku/profit_context" => "profit",
      "/ai/v3/sku/inventory_context" => "inventory",
      "/ai/v3/sku/lifecycle_context" => "lifecycle",
      "/ai/v3/sku/advertising_context" => "advertise_per_week",
      "/ai/v3/sku/orders_context" => "ec_orders_full_period",
      "/ai/v3/sku/supply_orders_context" => "supply_orders_full_period",
      "/ai/v3/sku/operation_actions_context" => "operation_actions_full_period",
      "/ai/v3/sku/warehouse_recommendation_context" => "warehouse_recommendation",
      "/ai/v3/sku/search_terms_context" => "search_terms_per_week"
    }

    travel_to Time.utc(2026, 8, 10, 12) do
      endpoints.each do |path, section_key|
        get path,
          params: { sku_code: @sku.sku_code.downcase, period_from: "2026-08-03", period_to: "2026-08-09" },
          headers: bearer_headers

        assert_response :success
        data = response.parsed_body.fetch("data")
        assert_equal 3, data.fetch("schema_version")
        assert_equal @sku.sku_code, data.fetch("sku_code")
        assert_equal(
          {
            "from" => "2026-08-03",
            "to" => "2026-08-09",
            "as_of" => "2026-08-10",
            "time_zone" => "Asia/Shanghai",
            "week_starts_on" => "monday"
          },
          data.fetch("period")
        )
        assert_equal (%w[period schema_version sku_code] + [section_key]).sort, data.keys.sort
        assert data.key?(section_key)
      end
    end
  end

  test "returns rendered markdown for text formats" do
    get "/ai/v3/sku/base_context.md",
      params: { sku_code: @sku.sku_code, period_from: "2026-08-03", period_to: "2026-08-09" },
      headers: bearer_headers

    assert_response :success
    assert_match "text/markdown", response.media_type
    assert_includes response.body, "# SKU context"
    assert_includes response.body, "- **sku_code:** #{@sku.sku_code}"
    assert_includes response.body, "## base"
    assert_includes response.body, "### sku_products"

    get "/ai/v3/sku/base_context",
      params: { sku_code: @sku.sku_code, period_from: "2026-08-03", period_to: "2026-08-09" },
      headers: bearer_headers.merge("Accept" => "text/plain")

    assert_response :success
    assert_match "text/markdown", response.media_type
    assert_includes response.body, "## base"
  end

  test "returns warehouse recommendation context using the requested sales period" do
    create_warehouse_sale(
      store: @ozon_store,
      platform: "ozon",
      platform_sku_id: @ozon_product.platform_sku_id,
      fulfillment_type: "fbo",
      cluster_to: "Москва",
      quantity: 14,
      ordered_at: @time_zone.local(2026, 8, 4, 12)
    )
    create_warehouse_sale(
      store: @ozon_store,
      platform: "ozon",
      platform_sku_id: @ozon_product.platform_sku_id,
      fulfillment_type: "fbo",
      cluster_to: "Казань",
      quantity: 70,
      ordered_at: @time_zone.local(2026, 7, 28, 12)
    )
    RawOzon::WarehouseCluster.create!(
      account: @ozon_account,
      warehouse_id: 91_001,
      warehouse_name: "ДОМОДЕДОВО_РФЦ",
      cluster_name: "Москва",
      country_name: "Россия",
      synced_at: @time_zone.local(2026, 8, 9, 8)
    )
    Ec::SkuInventoryLevel.create!(
      sku_code: @sku.sku_code,
      platform: "ozon",
      account_id: @ozon_account.id,
      store: @ozon_store,
      store_name: @ozon_store.store_name,
      fulfillment_type: "fbo",
      quantity: 3,
      is_latest: true,
      synced_at: @time_zone.local(2026, 8, 9, 9),
      warehouse_breakdown: [
        { warehouse_name: "ДОМОДЕДОВО_РФЦ", cluster_name: "Москва", quantity: 3, reserved: 1, promised: 2 }
      ]
    )
    Ec::SkuInventoryLevel.create!(
      sku_code: @sku.sku_code,
      platform: "ozon",
      account_id: @ozon_account.id,
      store: @ozon_store,
      store_name: @ozon_store.store_name,
      fulfillment_type: "inbound",
      quantity: 4,
      is_latest: true,
      synced_at: @time_zone.local(2026, 8, 9, 10)
    )

    get "/ai/v3/sku/warehouse_recommendation_context",
      params: {
        sku_code: @sku.sku_code,
        period_from: "2026-08-03",
        period_to: "2026-08-09",
        target_days: "14"
      },
      headers: bearer_headers

    assert_response :success
    context = response.parsed_body.dig("data", "warehouse_recommendation")
    assert_equal(
      { "from" => "2026-08-03", "to" => "2026-08-09", "days" => 7, "source" => "ec_orders.ordered_at" },
      context.fetch("sales_period")
    )
    assert_equal 14, context.fetch("target_days")

    ozon_store = context.fetch("stores").find { |store| store.fetch("platform") == "ozon" }
    assert_equal "available", ozon_store.fetch("data_status")
    assert_equal @ozon_store.id, ozon_store.fetch("store_id")
    assert_equal 14, ozon_store.dig("summary", "sales_quantity")
    assert_equal 2, ozon_store.dig("summary", "daily_sales")
    assert_equal 3, ozon_store.dig("summary", "available")
    assert_equal 4, ozon_store.dig("summary", "inbound")
    assert_equal 21, ozon_store.dig("summary", "recommended")

    assert_equal ["Москва"], ozon_store.fetch("sales_clusters").map { |cluster| cluster.fetch("cluster_name") }
    cluster = ozon_store.fetch("sales_clusters").sole
    assert_equal 14, cluster.fetch("sales_quantity")
    assert_equal 100, cluster.fetch("sales_share_pct")
    assert_equal 2, cluster.fetch("daily_sales")
    assert_equal 3, cluster.fetch("available")
    assert_equal 1, cluster.fetch("reserved")
    assert_equal 2, cluster.fetch("inbound")
    assert_equal 23, cluster.fetch("distribution_gap")
    assert_equal 1, cluster.fetch("receiving_warehouse_count")
    assert_equal(
      {
        "warehouse_name" => "ДОМОДЕДОВО_РФЦ",
        "warehouse_id" => nil,
        "cluster_name" => "Москва",
        "available" => 3,
        "reserved" => 1,
        "inbound" => 2
      },
      cluster.fetch("warehouses").sole
    )
  end

  test "requires authentication" do
    get "/ai/v3/sku/full_context"

    assert_response :unauthorized
  end

  test "rejects invalid funnel periods" do
    get "/ai/v3/sku/full_context",
      params: { sku_code: @sku.sku_code, period_from: "2026-08-04", period_to: "2026-08-09" },
      headers: bearer_headers

    assert_response :unprocessable_entity
    assert_equal "period_from_must_be_monday", response.parsed_body.fetch("error")
  end

  test "rejects invalid dates" do
    get "/ai/v3/sku/full_context",
      params: { sku_code: @sku.sku_code, period_from: "invalid", period_to: "2026-08-09" },
      headers: bearer_headers

    assert_response :unprocessable_entity
    assert_equal "invalid_date", response.parsed_body.fetch("error")
  end

  test "split context endpoints share period validation" do
    get "/ai/v3/sku/sales_funnel_context",
      params: { sku_code: @sku.sku_code, period_from: "2026-08-04", period_to: "2026-08-09" },
      headers: bearer_headers

    assert_response :unprocessable_entity
    assert_equal "period_from_must_be_monday", response.parsed_body.fetch("error")
  end

  private

  def bearer_headers
    { "Authorization" => "Bearer #{@raw_api_token}" }
  end

  def create_order(store, platform, platform_sku_id, status, quantity, **item_attributes)
    order = Ec::Order.create!(
      store: store,
      platform: platform,
      order_key: "#{platform}-#{@token}-#{quantity}",
      order_status: status,
      ordered_at: @time_zone.local(2026, 8, 4, 12),
      completed_at: @time_zone.local(2026, 8, 5, 12)
    )
    Ec::OrderItem.create!(
      {
        order: order,
        store: store,
        platform: platform,
        platform_sku_id: platform_sku_id,
        quantity: quantity
      }.merge(item_attributes)
    )
  end

  def create_operation_action(operation_type:, operated_at:, diff_result:)
    Ec::OperationAction.create!(
      operation_type: operation_type,
      operated_by_user: @user,
      operated_at: operated_at,
      sku_product: @ozon_product,
      sku: @sku,
      store: @ozon_store,
      diff_result: diff_result,
      record_by_system: true
    )
  end

  def create_warehouse_sale(store:, platform:, platform_sku_id:, fulfillment_type:, cluster_to:, quantity:, ordered_at:)
    suffix = SecureRandom.hex(3)
    order = Ec::Order.create!(
      store: store,
      platform: platform,
      order_key: "#{platform}-warehouse-#{@token}-#{suffix}",
      order_status: "delivered",
      ordered_at: ordered_at,
      completed_at: ordered_at + 1.day
    )
    fulfillment = order.fulfillments.create!(
      store: store,
      platform: platform,
      external_fulfillment_id: "#{platform}-warehouse-fulfillment-#{@token}-#{suffix}",
      fulfillment_key: "#{platform}-warehouse-#{@token}-#{suffix}",
      fulfillment_type: fulfillment_type,
      status: "delivered",
      cluster_to: cluster_to
    )
    order.items.create!(
      store: store,
      platform: platform,
      fulfillment: fulfillment,
      platform_sku_id: platform_sku_id,
      quantity: quantity
    )
  end
end
