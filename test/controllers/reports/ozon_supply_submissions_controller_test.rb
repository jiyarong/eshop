require "test_helper"

class Reports::OzonSupplySubmissionsControllerTest < ActionDispatch::IntegrationTest
  self.use_transactional_tests = true

  setup do
    @token = SecureRandom.hex(6).upcase
    @user = create_user_with_roles("supply-ui-#{@token}@example.com", "manager")
    @account = RawOzon::SellerAccount.create!(client_id: "supply-ui-#{@token}", api_key: "secret-not-for-page", company_type: "general")
    @store = Ec::Store.create!(platform: "ozon", store_name: "Supply UI #{@token}", company_type: "general", ozon_raw_account_id: @account.id)
    @sku = Ec::Sku.create!(sku_code: "SUPPLY-UI-#{@token}")
    Ec::SkuOperatorAssignment.create!(sku: @sku, user: @user)
    Ec::SkuProduct.create!(sku: @sku, store: @store, product_id: "10001", platform_sku_id: "1001")
    @sku.create_dimension!(inner_length_cm: 10, inner_width_cm: 10, inner_height_cm: 10, inner_box_weight_kg: 0.5,
      outer_length_cm: 40, outer_width_cm: 30, outer_height_cm: 20, outer_box_weight_kg: 10, outer_box_pcs: 4)
    RawOzon::WarehouseCluster.create!(account: @account, macrolocal_cluster_id: 761, cluster_name: "Москва",
      warehouse_id: 9001, warehouse_name: "MOSCOW_SUPPLY", synced_at: Time.current)
    Ec::SkuBatch.create!(sku: @sku, batch_code: "SUPPLY-UI-#{@token}", status: "received",
      purchased_quantity: 100, received_quantity: 100, purchase_unit_price_cny: 1)
    sign_in @user
  end

  test "starts from signed calculation preserving pallet quantities and deduplicating repeated submissions" do
    token = calculate_token
    sign_in @user
    assert_difference ["Ec::PalletPlan.count", "Ec::OzonSupplySubmission.count"], 1 do
      assert_enqueued_with(job: Ec::OzonSupplySubmissionJob) do
        post start_supply_reports_pallet_calculator_path(format: :json), params: supply_params(token)
      end
      assert_response :success
      @submission = Ec::OzonSupplySubmission.find(response.parsed_body.fetch("id"))
      sign_in @user
      post start_supply_reports_pallet_calculator_path(format: :json), params: supply_params(token)
      assert_response :success
      assert_equal @submission.id, response.parsed_body.fetch("id")
    end
    plan = @submission.pallet_plan
    assert_equal 2, plan.items.sole.boxes
    assert_equal 8, plan.items.sole.units
    assert_equal 8, plan.pallets.sole.items.sum(:units)
    assert_equal "draft", plan.status
    assert_equal "Asia/Shanghai", plan.time_zone
    assert_equal "queued", @submission.state
    assert_equal "DIRECT", @submission.data["supply_type"]
  end

  test "renders the full handoff and submission selectors without missing translations in every locale" do
    %w[zh en ru].each do |locale|
      sign_in @user
      post calculate_reports_pallet_calculator_path(locale: locale), params: calculation_params
      assert_response :success
      assert_select "form[action=?]", start_supply_reports_pallet_calculator_path(locale: locale)
      assert_select "input[name=calculation_token]"
      assert_select "[data-controller='association-picker']"
      assert_empty response.body.scan(/translation missing[^<"]*/i)
    end
    create_submission
    @submission.update!(state: "timeslot_required", draft_id: "123", data: {
      "supply_type" => "DIRECT", "warehouse_timezone" => "Europe/Moscow", "draft_created_at" => Time.current.iso8601,
      "warehouses" => [{ "storage_warehouse" => { "warehouse_id" => 9001, "name" => "Москва" } }],
      "timeslots" => [{ "from_in_timezone" => "2026-10-22T10:00:00", "to_in_timezone" => "2026-10-22T11:00:00" }]
    })
    %w[zh en ru].each do |locale|
      sign_in @user
      get reports_pallet_plan_path(@submission.pallet_plan, locale: locale)
      assert_response :success
      assert_select "form[action=?]", submit_supply_reports_pallet_plan_path(@submission.pallet_plan, locale: locale)
      assert_select "select[name=warehouse_id]"
      assert_select "select[name=timeslot_index]"
      assert_empty response.body.scan(/translation missing[^<"]*/i)
      assert_not_includes response.body, @account.api_key
    end
  end

  test "refuses a tampered calculation and rechecks SKU access before saving" do
    token = calculate_token
    sign_in @user
    assert_no_difference "Ec::PalletPlan.count" do
      post start_supply_reports_pallet_calculator_path(format: :json), params: supply_params(token + "tampered")
      assert_response :unprocessable_entity
      assert_equal "invalid_calculation", response.parsed_body["key"]
      Ec::SkuOperatorAssignment.where(sku_code: @sku.sku_code).delete_all
      sign_in @user
      post start_supply_reports_pallet_calculator_path(format: :json), params: supply_params(token)
      assert_response :unprocessable_entity
      assert_equal "sku_unavailable", response.parsed_body["key"]
    end
  end

  test "supports computed recommendations and limits API handoff to Ozon FBO" do
    params = calculation_params
    params[:items].sole.delete(:quantity)
    post calculate_reports_pallet_calculator_path, params: params
    assert_response :success
    assert_select "input[name=calculation_token]", count: 1
    sign_in @user
    post calculate_reports_pallet_calculator_path, params: calculation_params.merge(profile: "wb_mono")
    assert_response :success
    assert_select "input[name=calculation_token]", count: 0
  end

  test "status reads return local data without writes or queued API work and respect SKU visibility" do
    create_submission
    plan = @submission.pallet_plan
    sign_in @user
    assert_no_enqueued_jobs do
      assert_no_changes -> { @submission.reload.attributes } do
        get supply_submission_status_reports_pallet_plan_path(plan, format: :json)
      end
    end
    assert_response :success
    assert_equal "queued", response.parsed_body["state"]
    assert_equal "draft", response.parsed_body["plan_state"]
    assert_not_includes response.parsed_body["workflow_html"], confirm_reports_pallet_plan_path(plan)
    assert response.parsed_body["running"]
    assert_not_includes response.body, @account.api_key
    Ec::SkuOperatorAssignment.where(sku_code: @sku.sku_code).delete_all
    sign_in @user
    get supply_submission_status_reports_pallet_plan_path(plan, format: :json)
    assert_response :not_found
  end

  test "confirmation reserves stock and only enqueues creation after choosing a returned slot" do
    create_submission
    plan = @submission.pallet_plan
    @submission.update!(state: "timeslot_required", draft_id: "123", data: @submission.data.merge(
      "draft_created_at" => Time.current.iso8601, "timeslots" => [{ "from_in_timezone" => "2026-10-22T10:00:00", "to_in_timezone" => "2026-10-22T11:00:00" }]))
    sign_in @user
    assert_enqueued_with(job: Ec::OzonSupplySubmissionJob, args: [@submission.id]) do
      post submit_supply_reports_pallet_plan_path(plan, format: :json), params: { timeslot_index: "0" }
    end
    assert_response :success
    assert_equal "reserved", plan.reload.status
    assert_equal "order_queued", @submission.reload.state
    sign_in @user
    assert_no_enqueued_jobs do
      post submit_supply_reports_pallet_plan_path(plan, format: :json), params: { timeslot_index: "0" }
    end
    assert_response :unprocessable_entity
    assert_equal "invalid_status", response.parsed_body["key"]
    sign_in @user
    post bind_reports_pallet_plan_path(plan, format: :json), params: { supply_order_number: "unrelated" }
    assert_response :unprocessable_entity
    assert_equal "submission_in_progress", response.parsed_body["key"]
  end

  test "requires management permission for external submission" do
    token = calculate_token
    reader = create_user_with_roles("supply-reader-#{@token}@example.com", "auditor")
    sign_in reader
    assert_no_enqueued_jobs do
      post start_supply_reports_pallet_calculator_path(format: :json), params: supply_params(token)
    end
    assert_response :forbidden
  end

  test "local status query count and SQL length stay bounded when displaying more pallets" do
    create_submission
    plan = @submission.pallet_plan
    @submission.update!(state: "completed", order_id: "456")
    small = measure_status(plan)
    9.times { |index| plan.pallets.create!(position: index + 2, layout: {}, metrics: {}, ozon_cargo_id: (800 + index).to_s) }
    large = measure_status(plan)

    assert_operator large[:queries], :<=, small[:queries] + 1
    assert_operator large[:max_sql], :<=, small[:max_sql] + 100
    assert_equal 0, large[:inventory_records]
    assert_response :success
    assert_includes response.parsed_body.fetch("html"), "808"
  end

  private

  def measure_status(plan)
    sign_in @user
    metrics = { queries: 0, max_sql: 0, inventory_records: 0 }
    sql = lambda do |_name, _start, _finish, _id, payload|
      next if payload[:cached] || payload[:name].in?(%w[SCHEMA TRANSACTION])
      metrics[:queries] += 1
      metrics[:max_sql] = [metrics[:max_sql], payload[:sql].length].max
    end
    instantiation = lambda do |_name, _start, _finish, _id, payload|
      metrics[:inventory_records] += payload[:record_count] if payload[:class_name].in?(%w[Ec::SkuInventoryLevel Ec::SkuBatch Ec::Order])
    end
    ActiveRecord::Base.uncached do
      ActiveSupport::Notifications.subscribed(sql, "sql.active_record") do
        ActiveSupport::Notifications.subscribed(instantiation, "instantiation.active_record") do
          get supply_submission_status_reports_pallet_plan_path(plan, format: :json)
        end
      end
    end
    metrics
  end

  def calculation_params
    { profile: "ozon_fbo", items: [{ sku_code: @sku.sku_code, length: 40, width: 30, height: 20, weight: 10, pcs: 4, quantity: 2 }] }
  end

  def calculate_token
    sign_in @user
    post calculate_reports_pallet_calculator_path(format: :json), params: calculation_params
    assert_response :success
    response.parsed_body.fetch("calculation_token")
  end

  def supply_params(token)
    { calculation_token: token, store_id: @store.id, cluster_id: 761, supply_type: "DIRECT" }
  end

  def create_submission
    token = calculate_token
    sign_in @user
    post start_supply_reports_pallet_calculator_path(format: :json), params: supply_params(token)
    assert_response :success
    @submission = Ec::OzonSupplySubmission.find(response.parsed_body.fetch("id"))
  end
end
