require "test_helper"

class Reports::PalletWorkbenchesControllerTest < ActionDispatch::IntegrationTest
  setup do
    token = SecureRandom.hex(5)
    @user = create_user_with_roles("pallet-workbench-#{token}@example.com", "manager")
    @account = RawOzon::SellerAccount.create!(client_id: "pallet-workbench-#{token}", api_key: "test", company_type: "general")
    @store = Ec::Store.create!(platform: "ozon", store_name: "Workbench #{token}", company_type: "general", ozon_raw_account_id: @account.id)
    @cluster = RawOzon::WarehouseCluster.create!(account: @account, macrolocal_cluster_id: 771,
      cluster_name: "Москва", warehouse_id: 171, warehouse_name: "MOSCOW_WORKBENCH", synced_at: Time.current)
    sign_in @user
  end

  teardown do
    RawOzon::WarehouseCluster.where(account_id: @account.id).delete_all
    Ec::Store.where(id: @store.id).delete_all
    RawOzon::SellerAccount.where(id: @account.id).delete_all
    UserRole.where(user_id: @user.id).delete_all
    @user.destroy!
  end

  test "renders the Ozon store and cluster entry point in every supported locale" do
    %w[zh en ru].each do |locale|
      sign_in @user
      get reports_pallet_workbench_path(locale: locale, store_id: @store.id, cluster_id: @cluster.macrolocal_cluster_id)

      assert_response :success
      assert_select "h1", I18n.t("pallet_workbench.title", locale: locale)
      assert_select "select[name='cluster_id'] option[value='771']", text: /Москва.*0/
      assert_select "[data-controller='spu-sku-filter']", 1
      assert_select "[data-controller='time-range-selector']", 0
      assert_select "input[name='q']", 0
      assert_select "[data-controller='pallet-workbench']"
      assert_select "[data-pallet-workbench-target='mode'] option[value='single']"
      assert_select "[data-pallet-workbench-target='recommendButton']"
      assert_select "template button[data-pallet-workbench-target='maxButton'][title]", text: I18n.t("pallet_workbench.max_action", locale: locale)
      assert_select "[data-pallet-workbench-target='shippingAdvice'][aria-live='polite']", count: 1
      assert_select "#workbench-shipping-zone", count: 1
      assert_select "#workbench-shipping-date", count: 1
      assert_select ".pallet-workbench__advanced #workbench-shipping-zone", count: 0
      assert_select ".pallet-workbench__advanced #workbench-shipping-date", count: 0
      assert_select "[data-pallet-workbench-target='supplyButton']", count: 0
      assert_select "select[name='supply_type']", count: 0
      assert_select "th", text: I18n.t("delivery_workbench.sales", locale: locale)
      assert_no_match(/translation missing/i, response.body)
    end
  end

  test "keeps the GET entry point read-only" do
    assert_no_difference("Ec::PalletPlan.count") do
      get reports_pallet_workbench_path(store_id: @store.id, cluster_id: @cluster.macrolocal_cluster_id, format: :json)
    end

    assert_response :success
    assert_equal @store.id, response.parsed_body.fetch("store_id")
    assert_equal @cluster.macrolocal_cluster_id, response.parsed_body.fetch("cluster_id")
  end

  test "sorts target clusters by their aggregate shortage" do
    second_cluster = RawOzon::WarehouseCluster.create!(account: @account, macrolocal_cluster_id: 772,
      cluster_name: "Казань", warehouse_id: 172, warehouse_name: "KAZAN_WORKBENCH", synced_at: Time.current)
    sku = Ec::Sku.create!(sku_code: "CLUSTER-GAP-#{SecureRandom.hex(5).upcase}", product_name: "Cluster gap test")
    Ec::SkuOperatorAssignment.create!(sku: sku, user: @user)
    product = Ec::SkuProduct.create!(sku: sku, store: @store, product_id: sku.sku_code, platform_sku_id: sku.sku_code)
    sku.create_dimension!(outer_length_cm: 40, outer_width_cm: 30, outer_height_cm: 20, outer_box_weight_kg: 8, outer_box_pcs: 10)
    order = Ec::Order.create!(platform: "ozon", store: @store, order_key: "cluster-gap-#{SecureRandom.hex(5)}",
      order_status: "delivered", ordered_at: 3.days.ago)
    fulfillment = order.fulfillments.create!(platform: "ozon", store: @store,
      external_fulfillment_id: "CLUSTER-GAP-#{SecureRandom.hex(5)}", fulfillment_key: "cluster-gap-#{SecureRandom.hex(5)}",
      fulfillment_type: "fbo", status: "delivered", cluster_to: second_cluster.cluster_name)
    order.items.create!(platform: "ozon", store: @store, fulfillment: fulfillment,
      platform_sku_id: product.platform_sku_id, quantity: 56)
    Ec::SkuInventoryLevel.create!(sku: sku, store: @store, platform: "ozon", account_id: @account.id,
      fulfillment_type: "fbo", quantity: 0, is_latest: true, synced_at: Time.current,
      warehouse_breakdown: [{ warehouse_name: second_cluster.warehouse_name, cluster_name: second_cluster.cluster_name, quantity: 0 }])

    get reports_pallet_workbench_path(store_id: @store.id, format: :json)

    assert_response :success
    clusters = response.parsed_body.fetch("clusters")
    assert_equal [second_cluster.macrolocal_cluster_id, @cluster.macrolocal_cluster_id], clusters.map { |cluster| cluster.fetch("id") }
    assert_equal [56, 0], clusters.map { |cluster| cluster.fetch("shortage") }
  ensure
    Ec::OperationAction.where(ec_store_id: @store.id).delete_all
    Ec::OrderItem.where(store_id: @store.id).delete_all
    Ec::OrderFulfillment.where(store_id: @store.id).delete_all
    Ec::Order.where(store_id: @store.id).delete_all
    Ec::SkuInventoryLevel.where(store_id: @store.id).delete_all
    Ec::SkuProduct.where(id: product&.id).delete_all
    Ec::SkuOperatorAssignment.where(sku_code: sku&.sku_code).delete_all
    Ec::Sku.with_deleted.where(id: sku&.id).delete_all
  end

  test "previewing a reserved plan excludes its own stock reservation" do
    ActiveRecord::Base.transaction do
      sku = Ec::Sku.create!(sku_code: "PREVIEW-#{SecureRandom.hex(6).upcase}", product_name: "Preview test")
      Ec::SkuOperatorAssignment.create!(sku: sku, user: @user)
      sku.create_dimension!(inner_length_cm: 20, inner_width_cm: 10, inner_height_cm: 10, inner_box_weight_kg: 0.7,
        outer_length_cm: 40, outer_width_cm: 30, outer_height_cm: 20, outer_box_weight_kg: 8, outer_box_pcs: 10)
      product = Ec::SkuProduct.create!(sku: sku, store: @store, product_id: sku.sku_code, platform_sku_id: sku.sku_code)
      Ec::SkuBatch.create!(sku: sku, batch_code: sku.sku_code, status: "received",
        purchased_quantity: 10, received_quantity: 10, purchase_unit_price_cny: 1)
      plan = Ec::PalletPlan.create!(store: @store, created_by: @user, macrolocal_cluster_id: @cluster.macrolocal_cluster_id,
        cluster_name: @cluster.cluster_name, status: "reserved", from_date: Date.new(2026, 9, 18), to_date: Date.new(2026, 10, 15), target_days: 28, time_zone: "Asia/Shanghai")
      plan.items.create!(sku_product: product, sku_code: sku.sku_code, platform_sku_id: product.platform_sku_id, boxes: 1, pcs: 10, units: 10)

      attributes = {
        plan_id: plan.id, store_id: @store.id, cluster_id: @cluster.macrolocal_cluster_id,
        from_date: "2026-09-18", to_date: "2026-10-15", packing_mode: "single",
        items: [{ sku_code: sku.sku_code, quantity: 1 }]
      }
      %w[zh en ru].each do |locale|
        sign_in @user
        assert_no_difference("Ec::PalletPlan.count") do
          post preview_reports_pallet_workbench_path(format: :json, locale: locale), params: { pallet_plan: attributes }, as: :json
        end
        assert_response :success
        assert_equal 1, response.parsed_body.dig("result", "total_boxes")
        assert_nil response.parsed_body.dig("result", "shipping", "recommended")
        advice = response.parsed_body.fetch("shipping_advice_html")
        assert_includes advice, I18n.t("pallet_workbench.shipping.box_eligible", locale: locale)
        assert_includes advice, I18n.t("pallet_workbench.shipping.choose_zone", locale: locale)
        assert_select Nokogiri::HTML.fragment(advice), "button[data-mode='box'][data-action='pallet-workbench#useShippingMode']", count: 1
        assert_no_match(/translation missing/i, advice)
        assert_not response.parsed_body.key?("calculation_token")
      end

      snapshot = RawOzon::CrossDockTariffSnapshot.create!(market_code: "ru", effective_from: Date.new(2026, 10, 1),
        effective_to: Date.new(2026, 11, 1), source_file_name: "test.xlsx", source_checksum: SecureRandom.hex(16),
        imported_at: Time.current, status: "succeeded")
      RawOzon::CrossDockTariff.create!(snapshot: snapshot, supply_receiving_zone_name: "Zone A",
        supply_receiving_zone_key: "ZONE-A", destination_cluster_name: @cluster.cluster_name,
        destination_cluster_key: "МОСКВА", box_rub_per_l: 5, pallet_rub_per_l: 2.5)
      attributes[:shipping] = { supply_receiving_zone_key: "ZONE-A", shipping_date: "2026-10-21" }
      sign_in @user
      post preview_reports_pallet_workbench_path(format: :json, locale: :zh), params: { pallet_plan: attributes }, as: :json
      assert_response :success
      assert_equal "box", response.parsed_body.dig("result", "shipping", "recommended")
      assert_equal "lowest_cost", response.parsed_body.dig("result", "shipping", "recommendation_reason")
      assert_equal 4650, response.parsed_body.dig("result", "shipping", "savings").to_d
      assert_includes response.parsed_body.fetch("shipping_advice_html"), I18n.t("pallet_workbench.shipping.savings", amount: "4650.00", locale: :zh)

      attributes[:shipping_mode] = "box"
      sign_in @user
      assert_no_difference("Ec::PalletPlan.count") do
        post preview_reports_pallet_workbench_path(format: :json, locale: :zh), params: { pallet_plan: attributes }, as: :json
      end
      assert_response :success
      assert_equal "box", response.parsed_body.dig("result", "shipping_mode")
      assert_equal 1, response.parsed_body.dig("result", "total_boxes")
      assert_equal 10, response.parsed_body.dig("result", "total_units")
      assert_select Nokogiri::HTML.fragment(response.parsed_body.fetch("shipping_advice_html")), "button[data-mode='box']", count: 0

      attributes[:shipping] = { point_type: "pvz", shipping_date: "2026-10-21" }
      %w[zh en ru].each do |locale|
        sign_in @user
        post preview_reports_pallet_workbench_path(format: :json, locale: locale), params: { pallet_plan: attributes }, as: :json
        assert_response :success
        assert_equal "box", response.parsed_body.dig("result", "shipping", "recommended")
        assert_equal "only_available", response.parsed_body.dig("result", "shipping", "recommendation_reason")
        assert_nil response.parsed_body.dig("result", "shipping", "box", "cost")
        assert_includes response.parsed_body.fetch("shipping_advice_html"), I18n.t("pallet_workbench.shipping.only_available", locale: locale)
        assert_no_match(/translation missing/i, response.parsed_body.fetch("shipping_advice_html"))
      end
      raise ActiveRecord::Rollback
    end
  end

  test "fill and MAX previews ignore coverage in every supported locale without saving" do
    ActiveRecord::Base.transaction do
      sku = Ec::Sku.create!(sku_code: "FILL-LIMIT-#{SecureRandom.hex(6).upcase}", product_name: "Fill limit test")
      Ec::SkuOperatorAssignment.create!(sku: sku, user: @user)
      sku.create_dimension!(inner_length_cm: 20, inner_width_cm: 10, inner_height_cm: 10, inner_box_weight_kg: 0.7,
        outer_length_cm: 40, outer_width_cm: 40, outer_height_cm: 60, outer_box_weight_kg: 5, outer_box_pcs: 1)
      product = Ec::SkuProduct.create!(sku: sku, store: @store, product_id: sku.sku_code, platform_sku_id: sku.sku_code)
      Ec::SkuBatch.create!(sku: sku, batch_code: sku.sku_code, status: "received",
        purchased_quantity: 100, received_quantity: 100, purchase_unit_price_cny: 1)
      order = Ec::Order.create!(platform: "ozon", store: @store, order_key: sku.sku_code,
        order_status: "delivered", ordered_at: Time.zone.parse("2026-10-01 12:00:00"))
      fulfillment = order.fulfillments.create!(platform: "ozon", store: @store,
        external_fulfillment_id: sku.sku_code, fulfillment_key: sku.sku_code,
        fulfillment_type: "fbo", status: "delivered", cluster_to: @cluster.cluster_name)
      order.items.create!(platform: "ozon", store: @store, fulfillment: fulfillment,
        platform_sku_id: product.platform_sku_id, quantity: 5)

      %w[zh en ru].each do |locale|
        sign_in @user
        assert_no_difference("Ec::PalletPlan.count") do
          post preview_reports_pallet_workbench_path(format: :json, locale: locale), params: { pallet_plan: {
            store_id: @store.id, cluster_id: @cluster.macrolocal_cluster_id,
            from_date: "2026-09-23", to_date: "2026-10-20", target_days: 28, min_days: 21, max_days: 35,
            packing_mode: "single", fill_free_space: true, apply_fill: true,
            items: [{ sku_code: sku.sku_code, quantity: 6 }]
          } }, as: :json
        end
        assert_response :success
        result = response.parsed_body.fetch("result")
        assert_equal 18, result["total_boxes"]
        assert_equal 18, result.dig("fill", "changes", 0, "to_boxes")
        assert_equal "pallet_capacity", result.dig("fill", "limits", 0, "reason")
        assert_nil result.dig("fill", "limits", 0, "next_box_days")
        assert_includes response.parsed_body["html"], I18n.t("pallet_workbench.fill_summary", base: 6, final: 18, locale: locale)
        assert_no_match(/translation missing/i, response.parsed_body["html"])

        sign_in @user
        assert_no_difference("Ec::PalletPlan.count") do
          post preview_reports_pallet_workbench_path(format: :json, locale: locale), params: { pallet_plan: {
            store_id: @store.id, cluster_id: @cluster.macrolocal_cluster_id,
            from_date: "2026-09-23", to_date: "2026-10-20", target_days: 1, min_days: 1, max_days: 1,
            packing_mode: "single", maximize_sku_code: sku.sku_code,
            items: [{ sku_code: sku.sku_code, quantity: 6 }]
          } }, as: :json
        end
        assert_response :success
        assert_equal 18, response.parsed_body.dig("result", "maximized", "to_boxes")
        assert_equal 18, response.parsed_body.dig("result", "total_boxes")
        assert_no_match(/translation missing/i, response.parsed_body["html"])
      end
      raise ActiveRecord::Rollback
    end
  end
end
