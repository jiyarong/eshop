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

  test "starts from a saved plan using its actual manifest and deduplicates repeated submissions" do
    attributes = workbench_attributes
    attributes[:items].sole[:quantity] = 25
    attributes.merge!(recommend_one: true, settings: { height: 60 })
    plan = Ec::PalletPlans::Save.new(user: @user, attributes: attributes).call
    assert_operator plan.items.sole.boxes, :<, 25
    item_ids = plan.items.ids
    pallet_ids = plan.pallets.ids
    units = plan.items.sum(:units)

    sign_in @user
    assert_no_difference "Ec::PalletPlan.count" do
      assert_difference "Ec::OzonSupplySubmission.count", 1 do
        assert_enqueued_with(job: Ec::OzonSupplySubmissionJob) do
          post start_supply_reports_pallet_plan_path(plan, format: :json), params: {
            lock_version: plan.lock_version, store_id: -1, cluster_id: -1,
            items: [{ sku_code: @sku.sku_code, quantity: 100 }], supply_type: "DIRECT"
          }
        end
        assert_response :success
        submission_id = response.parsed_body.dig("supply_submission", "id")
        assert submission_id
        sign_in @user
        post start_supply_reports_pallet_plan_path(plan, format: :json), params: { lock_version: plan.lock_version }
        assert_response :success
        assert_equal submission_id, response.parsed_body.dig("supply_submission", "id")
      end
    end
    assert_equal item_ids, plan.reload.items.ids
    assert_equal pallet_ids, plan.pallets.ids
    assert_equal units, plan.pallets.sole.items.sum(:units)
    assert_equal @store.id, plan.store_id
    assert_equal 761, plan.macrolocal_cluster_id
    assert_equal "draft", plan.status
    assert_equal @user.id, plan.ozon_supply_submission.data["requested_by_id"]
    assert_nil plan.ozon_supply_submission.draft_id
    assert_nil plan.ozon_supply_submission.order_id
  end

  test "saved plan details offer delivery creation in every locale without performing writes" do
    plan = Ec::PalletPlans::Save.new(user: @user, attributes: workbench_attributes).call
    %w[zh en ru].each do |locale|
      sign_in @user
      assert_no_enqueued_jobs do
        assert_no_difference "Ec::OzonSupplySubmission.count" do
          get reports_pallet_plan_path(plan, locale: locale)
        end
      end
      assert_response :success
      assert_select "form[action=?]", start_supply_reports_pallet_plan_path(plan, locale: locale) do
        assert_select "input[name='lock_version'][value=?]", plan.lock_version.to_s
        assert_select "select[name='supply_type']"
        assert_select "input[type='submit'][value=?]", I18n.t("pallet_workbench.supply_api.plan_prepare", locale: locale)
      end
      assert_select "[data-association-picker-id-value=?]", "pallet-plan-#{plan.id}-drop-off"
      assert_empty response.body.scan(/translation missing[^<"]*/i)
      assert_not_includes response.body, @account.api_key
    end
    sign_in @user
    post start_supply_reports_pallet_plan_path(plan, locale: :ru), params: { lock_version: plan.lock_version }
    assert_response :see_other
    assert_redirected_to reports_pallet_plan_path(plan)
    sign_in @user
    get reports_pallet_plan_path(plan, locale: :zh)
    assert_response :success
    assert_select "form[action=?]", start_supply_reports_pallet_plan_path(plan, locale: :zh), count: 0
  end

  test "saved plan creation preserves manual multiple pallet allocations and crossdock choice" do
    attributes = workbench_attributes.merge(packing_mode: "multiple", allocations: [
      { items: [{ sku_code: @sku.sku_code, quantity: 1 }] }, { items: [{ sku_code: @sku.sku_code, quantity: 1 }] }
    ])
    plan = Ec::PalletPlans::Save.new(user: @user, attributes: attributes).call
    pallet_ids = plan.pallets.ids
    sign_in @user
    post start_supply_reports_pallet_plan_path(plan, format: :json), params: {
      lock_version: plan.lock_version, supply_type: "CROSSDOCK", drop_off: drop_off_selection("SORTING_CENTER")
    }
    assert_response :success
    assert_equal pallet_ids, plan.reload.pallets.ids
    assert_equal [4, 4], plan.pallets.map { |pallet| pallet.items.sum(:units) }
    submission = plan.ozon_supply_submission
    assert_equal "CROSSDOCK", submission.data["supply_type"]
    assert_equal({ "warehouse_id" => 9002, "warehouse_type" => "SORTING_CENTER" }, submission.data["drop_off"])
    assert_equal "Test receiving point", submission.data["drop_off_name"]
  end

  test "saved mixed plan preserves loose-box and pallet allocations when creating a delivery application" do
    attributes = workbench_attributes.merge(shipping_mode: "mixed")
    attributes[:items].sole[:quantity] = 2
    attributes[:items].sole[:box_quantity] = 1
    plan = Ec::PalletPlans::Save.new(user: @user, attributes: attributes).call
    expected = plan.pallets.joins(:items).reorder(nil).group(:cargo_type).sum("ec_pallet_items.boxes")

    sign_in @user
    get reports_pallet_plan_path(plan, locale: :zh)
    assert_response :success
    assert_includes response.body, I18n.t("pallet_workbench.manifest_box_quantity", locale: :zh)
    assert_includes response.body, I18n.t("pallet_workbench.manifest_pallet_quantity", locale: :zh)
    assert_includes response.body, I18n.t("pallet_workbench.box_cargo", number: 1, locale: :zh)

    sign_in @user
    get edit_reports_pallet_plan_path(plan, locale: :zh)
    assert_response :success
    initial_items = Nokogiri::HTML(response.body).at_css("[data-pallet-workbench-initial-value]")
    assert_equal 1, JSON.parse(initial_items["data-pallet-workbench-initial-value"]).sole.fetch("box_quantity")

    sign_in @user
    post start_supply_reports_pallet_plan_path(plan, format: :json), params: { lock_version: plan.lock_version }

    assert_response :success
    assert_equal({ "box" => 1, "pallet" => 1 }, expected)
    assert_equal expected, plan.reload.pallets.joins(:items).reorder(nil).group(:cargo_type).sum("ec_pallet_items.boxes")
    assert_equal "queued", plan.ozon_supply_submission.state
  end

  test "rejects pallets at a box-only point and accepts a valid box plan there" do
    pallet_plan = Ec::PalletPlans::Save.new(user: @user, attributes: workbench_attributes).call
    sign_in @user
    assert_no_difference "Ec::OzonSupplySubmission.count" do
      post start_supply_reports_pallet_plan_path(pallet_plan, format: :json), params: {
        lock_version: pallet_plan.lock_version, supply_type: "CROSSDOCK", drop_off: drop_off_selection("DELIVERY_POINT")
      }
    end
    assert_response :unprocessable_entity
    assert_equal "shipping_unavailable", response.parsed_body["key"]

    box_plan = Ec::PalletPlans::Save.new(user: @user,
      attributes: workbench_attributes.merge(shipping_mode: "box")).call
    sign_in @user
    post start_supply_reports_pallet_plan_path(box_plan, format: :json), params: {
      lock_version: box_plan.lock_version, supply_type: "CROSSDOCK", drop_off: drop_off_selection("DELIVERY_POINT")
    }
    assert_response :success
    assert_equal "queued", box_plan.reload.ozon_supply_submission.state
  end

  test "requires a signed receiving point from the plan's Ozon account" do
    plan = Ec::PalletPlans::Save.new(user: @user, attributes: workbench_attributes).call
    token = Ec::PalletPlans::StartOzonSupply.drop_off_verifier.generate({
      "account_id" => @account.id + 1, "warehouse_id" => 9002, "warehouse_type" => "SORTING_CENTER", "name" => "Other account"
    }, purpose: "drop-off", expires_in: 30.minutes)
    sign_in @user
    assert_no_difference "Ec::OzonSupplySubmission.count" do
      post start_supply_reports_pallet_plan_path(plan, format: :json), params: {
        lock_version: plan.lock_version, supply_type: "CROSSDOCK", drop_off: token
      }
    end
    assert_response :unprocessable_entity
    assert_equal "invalid_delivery", response.parsed_body["key"]
  end

  test "a reserved saved plan excludes its reservation and records the actual submitting user" do
    plan = Ec::PalletPlans::Save.new(user: @user, attributes: workbench_attributes).call
    creator = create_user_with_roles("supply-creator-#{@token}@example.com", "auditor")
    plan.update!(status: "reserved", created_by: creator)
    Ec::SkuBatch.find_by!(sku: @sku).update!(received_quantity: 8)
    sign_in @user
    assert_no_difference "Ec::PalletPlan.count" do
      post start_supply_reports_pallet_plan_path(plan, format: :json), params: { lock_version: plan.lock_version }
    end
    assert_response :success
    assert_equal "reserved", plan.reload.status
    assert_equal creator.id, plan.created_by_id
    assert_equal @user.id, plan.ozon_supply_submission.data["requested_by_id"]
    assert_equal 8, plan.items.sole.units
  end

  test "rejects a changed saved plan or one already bound to Ozon" do
    plan = Ec::PalletPlans::Save.new(user: @user, attributes: workbench_attributes).call
    old_version = plan.lock_version
    plan.update!(target_days: 30)
    sign_in @user
    assert_no_difference "Ec::OzonSupplySubmission.count" do
      post start_supply_reports_pallet_plan_path(plan, format: :json), params: { lock_version: old_version }
      assert_response :unprocessable_entity
      assert_equal "stale_plan", response.parsed_body["key"]
    end
    plan.update!(ozon_order_id: "already-bound")
    sign_in @user
    assert_no_difference "Ec::OzonSupplySubmission.count" do
      post start_supply_reports_pallet_plan_path(plan, format: :json), params: { lock_version: plan.lock_version }
      assert_response :unprocessable_entity
      assert_equal "not_editable", response.parsed_body["key"]
    end
    sign_in @user
    get reports_pallet_plan_path(plan, locale: :zh)
    assert_select "form[action=?]", start_supply_reports_pallet_plan_path(plan, locale: :zh), count: 0
  end

  test "replaces a cancelled submission from saved plan details without recreating the plan" do
    create_submission
    plan = @submission.pallet_plan
    @submission.update!(state: "cancelled")
    sign_in @user
    get reports_pallet_plan_path(plan, locale: :zh)
    assert_select "form[action=?]", start_supply_reports_pallet_plan_path(plan, locale: :zh)
    sign_in @user
    assert_no_difference ["Ec::PalletPlan.count", "Ec::OzonSupplySubmission.count"] do
      post start_supply_reports_pallet_plan_path(plan, format: :json), params: { lock_version: plan.lock_version }
    end
    assert_response :success
    assert_not_equal @submission.id, response.parsed_body.dig("supply_submission", "id")
    assert_equal "queued", plan.reload.ozon_supply_submission.state
  end

  test "rechecks saved plan inventory and access before creating a delivery application" do
    plan = Ec::PalletPlans::Save.new(user: @user, attributes: workbench_attributes).call
    Ec::SkuBatch.find_by!(sku: @sku).update!(received_quantity: 4)
    sign_in @user
    assert_no_difference "Ec::OzonSupplySubmission.count" do
      post start_supply_reports_pallet_plan_path(plan, format: :json), params: { lock_version: plan.lock_version }
    end
    assert_response :unprocessable_entity
    assert_equal "insufficient_stock", response.parsed_body["key"]

    Ec::SkuOperatorAssignment.where(sku_code: @sku.sku_code).delete_all
    sign_in @user
    assert_no_enqueued_jobs do
      post start_supply_reports_pallet_plan_path(plan, format: :json), params: { lock_version: plan.lock_version }
    end
    assert_response :not_found
  end

  test "rejects invalid saved pallet allocations and invalid delivery choices" do
    plan = Ec::PalletPlans::Save.new(user: @user, attributes: workbench_attributes).call
    sign_in @user
    assert_no_difference "Ec::OzonSupplySubmission.count" do
      post start_supply_reports_pallet_plan_path(plan, format: :json), params: { lock_version: plan.lock_version, supply_type: "CROSSDOCK" }
    end
    assert_response :unprocessable_entity
    assert_equal "invalid_delivery", response.parsed_body["key"]
    plan.pallets.sole.items.sole.update!(boxes: 1, units: 4)
    sign_in @user
    assert_no_difference "Ec::OzonSupplySubmission.count" do
      post start_supply_reports_pallet_plan_path(plan, format: :json), params: { lock_version: plan.lock_version }
    end
    assert_response :unprocessable_entity
    assert_equal "allocation_mismatch", response.parsed_body["key"]
  end

  test "requires management permission to start from saved plan details" do
    plan = Ec::PalletPlans::Save.new(user: @user, attributes: workbench_attributes).call
    reader = create_user_with_roles("plan-supply-reader-#{@token}@example.com", "auditor")
    sign_in reader
    assert_no_enqueued_jobs do
      post start_supply_reports_pallet_plan_path(plan, format: :json), params: { lock_version: plan.lock_version }
    end
    assert_response :forbidden
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

  test "starting a saved plan batches pallet item reads as the pallet count grows" do
    small_plan = Ec::PalletPlans::Save.new(user: @user, attributes: workbench_attributes).call
    attributes = workbench_attributes
    attributes[:items].sole[:quantity] = 10
    attributes.merge!(packing_mode: "multiple", allocations: Array.new(10) { { items: [{ sku_code: @sku.sku_code, quantity: 1 }] } })
    large_plan = Ec::PalletPlans::Save.new(user: @user, attributes: attributes).call

    small = measure_local_request do
      post start_supply_reports_pallet_plan_path(small_plan, format: :json), params: { lock_version: small_plan.lock_version }
    end
    assert_response :success
    large = measure_local_request do
      post start_supply_reports_pallet_plan_path(large_plan, format: :json), params: { lock_version: large_plan.lock_version }
    end
    assert_response :success
    assert_operator large[:queries], :<=, small[:queries] + 1
    assert_operator large[:max_sql], :<=, small[:max_sql] + 150
    assert_equal small[:inventory_records], large[:inventory_records]
    assert_equal 10, large_plan.reload.pallets.count
    assert_equal 40, large_plan.items.sum(:units)
  end

  private

  def workbench_attributes
    { store_id: @store.id, cluster_id: 761, from_date: "2026-09-18", to_date: "2026-10-15", packing_mode: "single",
      items: [{ sku_code: @sku.sku_code, quantity: 2 }] }
  end

  def measure_status(plan)
    measure_local_request { get supply_submission_status_reports_pallet_plan_path(plan, format: :json) }
  end

  def measure_local_request
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
          yield
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

  def drop_off_selection(type)
    Ec::PalletPlans::StartOzonSupply.drop_off_verifier.generate({
      "account_id" => @account.id, "warehouse_id" => 9002, "warehouse_type" => type, "name" => "Test receiving point"
    }, purpose: "drop-off", expires_in: 30.minutes)
  end

  def create_submission
    token = calculate_token
    sign_in @user
    post start_supply_reports_pallet_calculator_path(format: :json), params: supply_params(token)
    assert_response :success
    @submission = Ec::OzonSupplySubmission.find(response.parsed_body.fetch("id"))
  end
end
