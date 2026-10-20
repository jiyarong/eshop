require "test_helper"

class Reports::PalletPlansControllerTest < ActionDispatch::IntegrationTest
  self.use_transactional_tests = true

  setup do
    @token = SecureRandom.hex(6)
    @user = create_user_with_roles("pallet-binding-#{@token}@example.com", "manager")
    @account = RawOzon::SellerAccount.create!(client_id: "pallet-binding-#{@token}", api_key: "test", company_type: "general")
    @store = Ec::Store.create!(platform: "ozon", store_name: "Binding #{@token}", company_type: "general", ozon_raw_account_id: @account.id)
    @sku = Ec::Sku.create!(sku_code: "PALLET-BIND-#{@token.upcase}")
    Ec::SkuOperatorAssignment.create!(sku: @sku, user: @user)
    @product = Ec::SkuProduct.create!(sku: @sku, store: @store, product_id: "PRODUCT-#{@token}", platform_sku_id: "1001")
    @plan = create_plan
    item = @plan.items.create!(sku_code: @sku.sku_code, sku_product: @product, platform_sku_id: "1001", boxes: 1, pcs: 10, units: 10)
    @pallet = @plan.pallets.create!(position: 1, layout: {}, metrics: {})
    @pallet.items.create!(pallet_plan_item: item, boxes: 1, units: 10, layout: {})
    @order = create_supply("MATCH")
    sign_in @user
  end

  test "renders search and manual supply binding with the current store report link in every locale" do
    %w[zh en ru].each do |locale|
      sign_in @user
      get reports_pallet_plan_path(@plan, locale: locale)

      assert_response :success
      assert_select "[data-controller='association-picker'] input[type='hidden'][name='supply_order_number']"
      assert_select "[data-controller='association-picker'] input[role='combobox']"
      assert_select "[data-action='association-picker#openCreate']", count: 0
      assert_select "details input[type='text'][name='supply_order_number']"
      assert_select "[data-ozon-supply-status-url-value=?]", supply_submission_status_reports_pallet_plan_path(@plan, locale: locale)
      assert_select "a[href=?]", reports_supply_orders_path(store_ref: "ozon:#{@account.id}", locale: locale)
      assert_no_match(/translation missing/i, response.body)
    end
  end

  test "searches the current account and cluster and omits unrelated or already bound supplies" do
    create_supply("WRONG-CLUSTER", cluster_id: 762)
    create_supply("WRONG-SKU", platform_sku_id: 1002)
    create_supply("CANCELLED", status: "CANCELLED")
    bound_order = create_supply("BOUND")
    create_plan(ozon_order_id: bound_order.supply_order_id)
    other_account = RawOzon::SellerAccount.create!(client_id: "other-binding-#{@token}", api_key: "test", company_type: "general")
    create_supply("OTHER-ACCOUNT", account: other_account)

    assert_no_enqueued_jobs do
      assert_no_changes -> { @plan.reload.attributes } do
        get supply_orders_reports_pallet_plan_path(@plan, format: :json), params: { q: @token }
      end
    end

    assert_response :success
    assert_equal [@order.supply_order_id], response.parsed_body.map { |option| option.fetch("id") }
    assert_includes response.parsed_body.sole.fetch("label"), "OZON-MATCH-#{@token}"
  end

  test "accepts searches by order number parent ID and destination supply ID" do
    ["OZON-MATCH-#{@token}", @order.supply_order_id, "2000064845539"].each do |query|
      sign_in @user
      get supply_orders_reports_pallet_plan_path(@plan, format: :json), params: { q: query }

      assert_response :success
      assert_equal [@order.supply_order_id], response.parsed_body.map { |option| option.fetch("id") }
    end
  end

  test "binds a selected record using complete supply report details" do
    post bind_reports_pallet_plan_path(@plan, format: :json), params: { supply_order_number: @order.supply_order_id }

    assert_response :success
    assert_equal @order.supply_order_id, @plan.reload.ozon_order_id
    assert_equal "OZON-MATCH-#{@token}", @plan.supply_order_number
    assert_equal "2000064845539", @pallet.reload.ozon_supply_id
    assert_equal 9001, @pallet.storage_warehouse_id
  end

  test "manually binding an Ozon order number confirms a draft without marking it packed" do
    @plan.update!(status: "draft")

    post bind_reports_pallet_plan_path(@plan, format: :json), params: { supply_order_number: "  OZON-MATCH-#{@token}  " }

    assert_response :success
    assert_equal @order.supply_order_id, @plan.reload.ozon_order_id
    assert_equal "reserved", @plan.status
    assert @plan.confirmed_at
    assert_nil @plan.dispatched_at
    assert_nil @pallet.reload.ozon_cargo_id
  end

  test "manual numbers not yet imported are saved and matched in the background" do
    assert_enqueued_with(job: Ec::PalletPlanSyncJob, args: [{ plan_id: @plan.id }]) do
      post bind_reports_pallet_plan_path(@plan, format: :json), params: { supply_order_number: "NOT-YET-IMPORTED" }
    end

    assert_response :success
    assert_equal "NOT-YET-IMPORTED", @plan.reload.supply_order_number
    assert_nil @plan.ozon_order_id
    assert @plan.sync_error
    assert_equal "packed", @plan.status
  end

  test "retains manual binding after stopping automated creation" do
    @plan.create_ozon_supply_submission!(request_key: "cancelled-#{@token}", state: "cancelled")
    get reports_pallet_plan_path(@plan, locale: :zh)
    assert_response :success
    assert_select "details input[name='supply_order_number']"

    sign_in @user
    post bind_reports_pallet_plan_path(@plan, format: :json), params: { supply_order_number: @order.supply_order_id }
    assert_response :success
    assert_equal @order.supply_order_id, @plan.reload.ozon_order_id
    assert_equal "cancelled", @plan.ozon_supply_submission.state
  end

  test "hides and blocks manual binding while a platform write has an unknown order ID" do
    @plan.create_ozon_supply_submission!(request_key: "unknown-#{@token}", state: "review_required")
    get reports_pallet_plan_path(@plan, locale: :zh)
    assert_response :success
    assert_select "input[name='supply_order_number']", count: 0

    sign_in @user
    post bind_reports_pallet_plan_path(@plan, format: :json), params: { supply_order_number: @order.supply_order_id }
    assert_response :unprocessable_entity
    assert_equal "submission_in_progress", response.parsed_body.fetch("key")
    assert_nil @plan.reload.ozon_order_id
  end

  test "manual plan status polling reads local state and returns updated binding and workflow actions" do
    @plan.update!(status: "draft")
    Ec::PalletPlans::OzonReconciler.new(plan: @plan).bind!(@order.supply_order_id, enqueue: false)

    assert_no_enqueued_jobs do
      assert_no_changes -> { @plan.reload.attributes } do
        get supply_submission_status_reports_pallet_plan_path(@plan, format: :json, locale: :zh)
      end
    end

    assert_response :success
    data = response.parsed_body
    assert_nil data["state"]
    assert_equal "reserved", data["plan_state"]
    assert_equal @order.supply_order_id, data["order_id"]
    assert_equal "OZON-MATCH-#{@token}", data["order_number"]
    assert_includes data["binding_html"], "OZON-MATCH-#{@token}"
    assert_includes data["workflow_html"], advance_reports_pallet_plan_path(@plan)
    assert_equal "", data["handoff_html"]
    assert_not data["running"]
    assert data["active"]
    assert_not_includes response.body, @account.api_key
  end

  test "rechecks supply quantities at binding after a record was selected" do
    @order.supply_order_items.sole.update!(quantity: 11)

    post bind_reports_pallet_plan_path(@plan, format: :json), params: { supply_order_number: @order.supply_order_id }

    assert_response :unprocessable_entity
    assert_equal "supply_mismatch", response.parsed_body.fetch("key")
    assert_nil @plan.reload.ozon_order_id
    assert_nil @pallet.reload.ozon_supply_id
  end

  test "does not expose supplies through a plan with invisible SKUs" do
    Ec::SkuOperatorAssignment.where(sku_code: @sku.sku_code).delete_all

    get supply_orders_reports_pallet_plan_path(@plan, format: :json), params: { q: @token }

    assert_response :not_found
  end

  test "requires management permission to search binding candidates" do
    reader = create_user_with_roles("pallet-reader-#{@token}@example.com", "auditor")
    sign_in reader

    get supply_orders_reports_pallet_plan_path(@plan, format: :json), params: { q: @token }

    assert_response :forbidden
  end

  private

  def create_plan(**attributes)
    Ec::PalletPlan.create!({ store: @store, created_by: @user, macrolocal_cluster_id: 761,
      cluster_name: "Москва", status: "packed", from_date: Date.new(2026, 7, 1),
      to_date: Date.new(2026, 7, 28), target_days: 28, time_zone: "Asia/Shanghai" }.merge(attributes))
  end

  def create_supply(number, account: @account, cluster_id: 761, platform_sku_id: 1001, status: "READY_TO_SUPPLY")
    order = RawOzon::SupplyOrder.create!(account: account, supply_order_id: "ORDER-#{number}-#{@token}", status: status,
      items: { "1001" => 999 }, raw_json: { "order_number" => "OZON-#{number}-#{@token}" }, synced_at: Time.current)
    order.supply_order_items.create!(bundle_id: "BUNDLE-#{number}-#{@token}", ozon_supply_id: 2_000_064_845_539,
      platform_sku_id: platform_sku_id, quantity: 10, state: status, macrolocal_cluster_id: cluster_id,
      storage_warehouse_id: 9001, synced_at: Time.current)
    order
  end
end
