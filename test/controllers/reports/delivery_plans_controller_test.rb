require "test_helper"

class Reports::DeliveryPlansControllerTest < ActionDispatch::IntegrationTest
  self.use_transactional_tests = true

  setup do
    @previous_locales = I18n.available_locales
    I18n.available_locales = %i[zh en ru]
    token = SecureRandom.hex(5).upcase
    @user = create_user_with_roles("delivery-controller-#{token}@example.com", "manager")
    @account = RawOzon::SellerAccount.create!(client_id: "delivery-controller-#{token}", api_key: "test", company_type: "general")
    @store = Ec::Store.create!(platform: "ozon", store_name: "Delivery #{token}", company_type: "general", ozon_raw_account_id: @account.id)
    @cluster = RawOzon::WarehouseCluster.create!(account: @account, macrolocal_cluster_id: 781,
      cluster_name: "Москва", warehouse_id: 181, warehouse_name: "DELIVERY_CONTROLLER", synced_at: Time.current)
    @sku = Ec::Sku.create!(sku_code: "DELIVERY-CONTROLLER-#{token}")
    Ec::SkuOperatorAssignment.create!(sku: @sku, user: @user)
    @product = Ec::SkuProduct.create!(sku: @sku, store: @store, product_id: token, platform_sku_id: "10001")
    sign_in @user
  end

  teardown { I18n.available_locales = @previous_locales }

  test "renders SKU-first delivery planning without requiring a shortage cluster in every locale" do
    %w[zh en ru].each do |locale|
      sign_in @user
      assert_no_difference ["Ec::DeliveryPlan.count", "Ec::PalletPlan.count"] do
        assert_no_enqueued_jobs { get reports_delivery_workbench_path(locale: locale, store_id: @store.id) }
      end
      assert_response :success
      assert_select "h1", I18n.t("delivery_workbench.title", locale: locale)
      assert_select "[data-controller='delivery-workbench']"
      assert_select "[data-controller='spu-sku-filter']", 1
      assert_select "[data-controller='time-range-selector']", 1
      assert_select "input[data-sku='#{@sku.sku_code}']", 1
      assert_select "template input[type='number'][required]", 0
      assert_select "select[name='cluster_id'] option[value='781']"
      assert_select "[data-pallet-workbench-target='mode']", 0
      assert_select "[data-pallet-workbench-target='calculateButton']", 0
      assert_no_match(/translation missing/i, response.body)
    end
  end

  test "keeps zero-shortage clusters available and allows a manual delivery plan" do
    get reports_delivery_workbench_path(store_id: @store.id, format: :json)

    assert_response :success
    cluster = response.parsed_body.fetch("clusters").sole
    assert_equal @cluster.macrolocal_cluster_id, cluster.fetch("id")
    assert_equal 0, cluster.fetch("shortage")
    row = response.parsed_body.fetch("rows").find { |entry| entry.fetch("sku_code") == @sku.sku_code }
    assert_equal 0, row.fetch("suggested_units")

    sign_in @user
    post reports_delivery_plans_path(format: :json), params: { delivery_plan: attributes.merge(items: [{ sku_code: @sku.sku_code, units: 17 }]) }
    assert_response :success
    assert_equal 17, Ec::DeliveryPlan.find(response.parsed_body.fetch("id")).items.sole.units
  end

  test "creates reads lists and edits independent delivery plans through HTML and JSON" do
    assert_difference("Ec::DeliveryPlan.count") do
      post reports_delivery_plans_path(format: :json), params: { delivery_plan: attributes }
    end
    assert_response :success
    plan = Ec::DeliveryPlan.find(response.parsed_body.fetch("id"))
    assert_equal 103, plan.items.sole.units
    %w[zh en ru].each do |locale|
      sign_in @user
      sign_in @user
      get reports_delivery_plan_path(plan, locale: locale)
      assert_response :success
      assert_select "a[href=?]", reports_pallet_workbench_path(delivery_plan_id: plan.id, locale: locale)
      assert_no_match(/translation missing/i, response.body)
      sign_in @user
      get edit_reports_delivery_plan_path(plan, locale: locale)
      assert_response :success
      assert_select "[data-delivery-workbench-initial-value]"
      sign_in @user
      get reports_delivery_plans_path(locale: locale)
      assert_response :success
      assert_select "a[href=?]", reports_delivery_plan_path(plan, locale: locale)
    end
    sign_in @user
    patch reports_delivery_plan_path(plan, format: :json), params: { delivery_plan: attributes.merge(lock_version: plan.lock_version,
      items: [{ sku_code: @sku.sku_code, units: 105 }]) }
    assert_response :success
    assert_equal 105, plan.items.reload.sole.units
    sign_in @user
    get reports_delivery_plan_path(plan, format: :json)
    assert_response :success
    assert_equal({}, response.parsed_body.fetch("allocated_units"))
    assert_equal 105, response.parsed_body.fetch("items").sole.fetch("units")
  end

  test "packing context keeps estimates advisory and stock available above the estimate" do
    @sku.create_dimension!(inner_length_cm: 20, inner_width_cm: 10, inner_height_cm: 10, inner_box_weight_kg: 1,
      outer_length_cm: 40, outer_width_cm: 30, outer_height_cm: 20, outer_box_weight_kg: 8, outer_box_pcs: 10)
    @sku.batches.create!(status: "received", received_quantity: 100, purchased_quantity: 100)
    delivery = Ec::DeliveryPlans::Save.new(user: @user, attributes: attributes).call
    sign_in @user
    get reports_pallet_workbench_path(delivery_plan_id: delivery.id, format: :json)
    assert_response :success
    # Saved demand remains packable even when the latest sales-based gap is zero.
    assert_equal 10, response.parsed_body.fetch("rows").sole.fetch("suggested_boxes")
    assert_nil response.parsed_body.fetch("rows").sole.fetch("exclusion_reason")
    %w[zh en ru].each do |locale|
      sign_in @user
      get reports_pallet_workbench_path(delivery_plan_id: delivery.id, locale: locale)
      assert_response :success
      assert_select "th", text: I18n.t("delivery_workbench.packable_units", locale: locale)
      assert_select "a[href*=?]", "/reports/delivery_plans/#{delivery.id}"
      assert_no_match(/translation missing/i, response.body)
    end
    # A draft contributes to the total but does not cap further packing to the estimate.
    batch = delivery.packing_plans.create!(store: @store, created_by: @user, macrolocal_cluster_id: @cluster.macrolocal_cluster_id,
      cluster_name: @cluster.cluster_name, from_date: delivery.from_date, to_date: delivery.to_date, time_zone: "Asia/Shanghai")
    batch.items.create!(sku_product: @product, sku_code: @sku.sku_code, platform_sku_id: "10001", boxes: 10, pcs: 10, units: 100)
    sign_in @user
    get reports_pallet_workbench_path(delivery_plan_id: delivery.id, format: :json)
    assert_response :success
    row = response.parsed_body.fetch("rows").sole
    assert_equal @sku.sku_code, row.fetch("sku_code")
    assert_equal 3, row.fetch("shortage")
    assert_equal 100, row.fetch("fbs_allocatable")
    assert_equal 1, row.fetch("suggested_boxes")
  end

  test "saves a SKU without an estimate and determines quantities during packing" do
    post reports_delivery_plans_path(format: :json), params: { delivery_plan: attributes.merge(items: [{ sku_code: @sku.sku_code }]) }
    assert_response :success
    delivery = Ec::DeliveryPlan.find(response.parsed_body.fetch("id"))
    assert_nil delivery.items.sole.units
    @sku.create_dimension!(inner_length_cm: 20, inner_width_cm: 10, inner_height_cm: 10, inner_box_weight_kg: 1,
      outer_length_cm: 40, outer_width_cm: 30, outer_height_cm: 20, outer_box_weight_kg: 8, outer_box_pcs: 10)
    @sku.batches.create!(status: "received", received_quantity: 100, purchased_quantity: 100)
    packing = attributes.except(:week_start).merge(delivery_plan_id: delivery.id, shipping_mode: "box",
      items: [{ sku_code: @sku.sku_code, quantity: 2 }])
    sign_in @user
    post preview_reports_pallet_workbench_path(format: :json), params: { pallet_plan: packing }
    assert_response :success
    assert_equal 2, response.parsed_body.fetch("result").fetch("items").sole.fetch("quantity")
    sign_in @user
    post reports_pallet_plans_path(format: :json), params: { pallet_plan: packing }
    assert_response :success
    batch = delivery.packing_plans.sole
    assert_equal 20, batch.items.sole.units
    sign_in @user
    patch reports_delivery_plan_path(delivery, format: :json), params: { delivery_plan: attributes.merge(lock_version: delivery.lock_version,
      items: [{ sku_code: @sku.sku_code, units: 1 }]) }
    assert_response :success
    sign_in @user
    patch reports_pallet_plan_path(batch, format: :json), params: { pallet_plan: packing.merge(items: [{ sku_code: @sku.sku_code, quantity: 3 }]) }
    assert_response :success
    sign_in @user
    get reports_delivery_plan_path(delivery, format: :json)
    assert_response :success
    assert_equal({ @sku.sku_code => 30 }, response.parsed_body.fetch("allocated_units"))
    sign_in @user
    patch reports_delivery_plan_path(delivery, format: :json), params: { delivery_plan: attributes.merge(lock_version: delivery.reload.lock_version,
      items: [{ sku_code: @sku.sku_code, units: "" }]) }
    assert_response :success
    %w[zh en ru].each do |locale|
      sign_in @user
      get reports_delivery_plan_path(delivery, locale: locale)
      assert_response :success
      assert_select "td", text: I18n.t("delivery_workbench.quantity_pending", locale: locale), count: 2
      assert_select "td", text: "30", count: 1
      assert_no_match(/translation missing/i, response.body)
      sign_in @user
      get edit_reports_delivery_plan_path(delivery, locale: locale)
      assert_response :success
      initial = Nokogiri::HTML(response.body).at_css("[data-delivery-workbench-initial-value]")["data-delivery-workbench-initial-value"]
      assert_nil JSON.parse(initial).sole.fetch("units")
      sign_in @user
      get reports_pallet_workbench_path(delivery_plan_id: delivery.id, locale: locale)
      assert_response :success
      assert_select "th", text: I18n.t("delivery_workbench.reference_units", locale: locale)
      assert_no_match(/translation missing/i, response.body)
    end
  end

  test "hides an entire delivery plan when any SKU is outside the current users scope" do
    plan = Ec::DeliveryPlans::Save.new(user: @user, attributes: attributes).call
    hidden = Ec::Sku.create!(sku_code: "HIDDEN-#{SecureRandom.hex(5).upcase}")
    plan.items.create!(sku_code: hidden.sku_code, units: 1)
    sign_in @user
    get reports_delivery_plans_path(format: :json)
    assert_response :success
    refute_includes response.parsed_body.map { |row| row.fetch("id") }, plan.id
    sign_in @user
    get reports_delivery_plan_path(plan, format: :json)
    assert_response :not_found
    sign_in @user
    get reports_pallet_workbench_path(delivery_plan_id: plan.id, format: :json)
    assert_response :not_found
    sign_in @user
    patch reports_delivery_plan_path(plan, format: :json), params: { delivery_plan: attributes.merge(lock_version: plan.lock_version) }
    assert_response :not_found
  end

  test "packing without estimates can still select sales based suggestions automatically" do
    delivery = Ec::DeliveryPlans::Save.new(user: @user, attributes: attributes.merge(items: [{ sku_code: @sku.sku_code }])).call
    @sku.create_dimension!(inner_length_cm: 20, inner_width_cm: 10, inner_height_cm: 10, inner_box_weight_kg: 1,
      outer_length_cm: 40, outer_width_cm: 30, outer_height_cm: 20, outer_box_weight_kg: 8, outer_box_pcs: 10)
    @sku.batches.create!(status: "received", received_quantity: 100, purchased_quantity: 100)
    order = Ec::Order.create!(platform: "ozon", store: @store, order_key: "delivery-auto-#{SecureRandom.hex(5)}",
      order_status: "delivered", ordered_at: Time.zone.parse("2026-10-07 12:00:00"))
    fulfillment = order.fulfillments.create!(platform: "ozon", store: @store,
      external_fulfillment_id: "DELIVERY-AUTO-#{SecureRandom.hex(5)}", fulfillment_key: "delivery-auto-#{SecureRandom.hex(5)}",
      fulfillment_type: "fbo", status: "delivered", cluster_to: @cluster.cluster_name)
    order.items.create!(platform: "ozon", store: @store, fulfillment: fulfillment,
      platform_sku_id: @product.platform_sku_id, quantity: 28)
    sign_in @user
    post auto_select_reports_pallet_workbench_path(format: :json), params: { delivery_plan_id: delivery.id, shortage_gt: 0 }
    assert_response :success
    assert_equal [{ "sku_code" => @sku.sku_code, "quantity" => 3 }], response.parsed_body.fetch("items")
  end

  test "rejects hidden SKUs and users without management permission on writes" do
    hidden = Ec::Sku.create!(sku_code: "HIDDEN-#{SecureRandom.hex(5).upcase}")
    Ec::SkuProduct.create!(sku: hidden, store: @store, product_id: hidden.sku_code, platform_sku_id: "10002")
    sign_in @user
    post reports_delivery_plans_path(format: :json), params: { delivery_plan: attributes.merge(items: [{ sku_code: hidden.sku_code, units: 1 }]) }
    assert_response :unprocessable_entity
    assert_equal "sku_unavailable", response.parsed_body.fetch("key")
    @user.roles.clear
    @user.roles << Role.find_by!(code: "operator")
    sign_in @user
    sign_in @user
    post reports_delivery_plans_path(format: :json), params: { delivery_plan: attributes }
    assert_response :forbidden
  end

  test "cancels only after all packing batches are cancelled" do
    plan = Ec::DeliveryPlans::Save.new(user: @user, attributes: attributes).call
    batch = plan.packing_plans.create!(store: @store, created_by: @user, macrolocal_cluster_id: @cluster.macrolocal_cluster_id,
      cluster_name: @cluster.cluster_name, from_date: plan.from_date, to_date: plan.to_date, time_zone: "Asia/Shanghai")
    sign_in @user
    post cancel_reports_delivery_plan_path(plan, format: :json)
    assert_response :unprocessable_entity
    assert_equal "delivery_has_packages", response.parsed_body.fetch("key")
    batch.update!(status: "cancelled")
    sign_in @user
    post cancel_reports_delivery_plan_path(plan, format: :json)
    assert_response :success
    assert_equal "cancelled", plan.reload.status
    sign_in @user
    get edit_reports_delivery_plan_path(plan, format: :json)
    assert_response :unprocessable_entity
  end

  test "listing queries stay bounded when more delivery plans are displayed" do
    Ec::DeliveryPlans::Save.new(user: @user, attributes: attributes).call
    counts = []
    [1, 6].each do |size|
      5.times { Ec::DeliveryPlans::Save.new(user: @user, attributes: attributes).call } if size == 6
      sign_in @user
      queries = []
      subscriber = ->(event) do
        payload = event.payload
        queries << payload[:sql] if !payload[:cached] && payload[:sql].match?(/SELECT.*(?:ec_delivery_|ec_stores)/m)
      end
      ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
        ActiveRecord::Base.uncached { get reports_delivery_plans_path(locale: :zh) }
      end
      assert_response :success
      assert_select "table tbody tr", size
      counts << queries.size
      assert_operator queries.map(&:length).max, :<, 2000
    end
    assert_equal counts.first, counts.last
  end

  private

  def attributes
    { store_id: @store.id, cluster_id: @cluster.macrolocal_cluster_id, week_start: "2026-10-21",
      from_date: "2026-09-21", to_date: "2026-10-18", target_days: 28, time_zone: "Asia/Shanghai",
      items: [{ sku_code: @sku.sku_code, units: 103 }] }
  end
end
