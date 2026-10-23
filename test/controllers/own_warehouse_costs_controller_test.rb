require "test_helper"

class OwnWarehouseCostsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @code = "OWC-#{SecureRandom.hex(5).upcase}"
    @week = Date.new(2026, 6, 1)
    @user = create_user_with_roles("#{@code.downcase}@example.com", "super_admin")
    @sku = Ec::Sku.create!(sku_code: @code)
    sign_in @user
  end

  teardown do
    if @system_period
      Ec::OwnWarehouseSkuCostAllocation.where(own_warehouse_cost_period_id: @system_period.id).delete_all
      Ec::OperationLog.where(record_type: "Ec::OwnWarehouseCostPeriod", record_id: @system_period.id).delete_all
      @system_period.delete
    end
    Ec::Snapshot.where(sku_id: @sku.id).delete_all
    if @excluded_sku
      Ec::Snapshot.where(sku_id: @excluded_sku.id).delete_all
      Ec::OperationLog.where(record_type: "Ec::Sku", record_id: @excluded_sku.id).delete_all
      @excluded_sku.delete
    end
    Ec::OwnWarehouseSkuCostAllocation.where(own_warehouse_code: @code).delete_all
    periods = Ec::OwnWarehouseCostPeriod.where(own_warehouse_code: @code)
    Ec::OperationLog.where(record_type: "Ec::OwnWarehouseCostPeriod", record_id: periods.select(:id)).delete_all
    periods.delete_all
    Ec::SkuDeveloperAssignment.where(sku_code: @code).delete_all
    Ec::OperationLog.where(record_type: "Ec::Sku", record_id: @sku.id).delete_all
    Ec::Sku.with_deleted.where(id: @sku.id).delete_all
    UserRole.where(user_id: @user.id).delete_all
    @user.destroy!
  end

  test "configuration page displays a form creates draft confirms and copies version" do
    get own_warehouse_costs_path, params: { new_version: "1" }, headers: { "Accept" => "text/html" }
    assert_response :success
    assert_select "form[action=?][method='post']", own_warehouse_costs_path
    assert_select "input[name='ec_own_warehouse_cost_period[billing_unit]']", count: 0
    assert_select "input[name='ec_own_warehouse_cost_period[effective_to]'][required]", count: 0
    assert_select "input[name='ec_own_warehouse_cost_period[cost_basis_days]'][value='7'][required]", count: 1
    post own_warehouse_costs_path(format: :json), params: { ec_own_warehouse_cost_period: period_params.merge(effective_to: "", cost_basis_days: 14) }
    assert_response :success
    period = Ec::OwnWarehouseCostPeriod.find(JSON.parse(response.body)["id"])
    assert period.draft?
    post confirm_own_warehouse_cost_path(period, format: :json)
    assert_response :success
    assert period.reload.confirmed?
    assert_nil period.effective_to
    assert_equal 50.to_d, period.daily_cost_on(@week + 7)
    patch own_warehouse_cost_path(period, format: :json), params: { ec_own_warehouse_cost_period: { total_operating_cost: 1 } }
    assert_response :unprocessable_entity
    assert_equal 700.to_d, period.reload.total_operating_cost
    get own_warehouse_costs_path, params: { version_id: period.id, new_version: "1" }, headers: { "Accept" => "text/html" }
    assert_response :success
    assert_select "input[name='ec_own_warehouse_cost_period[total_operating_cost]'][value='700.0']"
    assert_select "fieldset[disabled]", count: 0
    assert_select "input[name='ec_own_warehouse_cost_period[effective_to]'][value]", count: 0
    assert_select "input[name='ec_own_warehouse_cost_period[cost_basis_days]'][value='14']", count: 1
    %w[zh en ru].each do |locale|
      get own_warehouse_costs_path, params: { version_id: period.id, locale: locale }, headers: { "Accept" => "text/html" }
      assert_response :success
      assert_no_match(/translation missing/i, response.body)
      assert_select "fieldset[disabled]", count: 1
    end
  end

  test "daily CSV produces a weekly revision and GET is read only in all locales" do
    period = Ec::OwnWarehouseCostPeriod.create!(period_params)
    period.confirm!(actor: @user)
    csv = CSV.generate do |out|
      out << %w[date sku_code unit_volume_m3 on_hand_quantity fbs_outbound_quantity fbo_outbound_quantity]
      7.times { |day| out << [@week + day, @code, 0.01, 100, 2, 1] }
    end
    file = Tempfile.new(["own-warehouse", ".csv"])
    file.write(csv); file.flush
    post calculate_own_warehouse_sku_costs_path(format: :json), params: { week_start: @week, own_warehouse_code: @code, complete_population: "1", file: Rack::Test::UploadedFile.new(file.path, "text/csv") }
    assert_response :success
    assert_equal 700.to_d, Ec::OwnWarehouseSkuCostAllocation.where(own_warehouse_code: @code).current.sum(:total_cost)
    %w[zh en ru].each do |locale|
      assert_no_difference "Ec::OwnWarehouseSkuCostAllocation.count" do
        get own_warehouse_sku_costs_path, params: { from_date: @week, to_date: @week + 6, own_warehouse_code: @code, locale: locale }, headers: { "Accept" => "text/html" }
      end
      assert_response :success
      assert_select "[data-controller='time-range-selector'][data-time-range-selector-submit-on-apply-value='true']", count: 1
      assert_select ".page-h form[action=?]", calculate_own_warehouse_costs_path do
        assert_select "input[name='week_start'][value=?]", @week.to_s
        assert_select "input[name='own_warehouse_code'][value=?]", @code
        assert_select "input[name='source'][value='system']"
        assert_select "button", text: I18n.t("own_warehouse.regenerate_week", locale: locale)
      end
      assert_select "input[name='developer_id'], input[name='operator_id'], select[name='developer_id'], select[name='operator_id']", count: 0
      assert_select ".own-warehouse-import, input[type='file'], input[type='date'][name='week_start']", count: 0
      assert_select "td", text: @code
      assert_no_match(/translation missing/i, response.body)
    end
    get own_warehouse_costs_path, params: { tab: "allocations", from_date: @week, to_date: @week + 6, own_warehouse_code: @code }, headers: { "Accept" => "text/html" }
    assert_response :success
    assert_select "a#own-warehouse-allocations-tab[aria-current='page']"
    assert_select "#own-warehouse-allocations-panel [data-controller='time-range-selector']", count: 1
    assert_select ".own-warehouse-rate-panel", count: 1
    assert_select ".own-warehouse-rate-table tbody tr", count: 1
    assert_select ".own-warehouse-table th", text: /FBS/, minimum: 1
    assert_select ".own-warehouse-table th", text: /FBO/, minimum: 1
    assert_select "a#own-warehouse-config-tab[aria-current='page']", count: 0
    get own_warehouse_sku_costs_path(format: :json), params: { from_date: @week, to_date: @week + 6, own_warehouse_code: @code }
    assert_response :success
    assert_equal 1, JSON.parse(response.body)["rows"].size
  ensure
    file&.close!
  end

  test "template contains every active SKU for all seven days" do
    get template_own_warehouse_costs_path, params: { week_start: @week, own_warehouse_code: @code }
    assert_response :success
    rows = CSV.parse(response.body, headers: true)
    assert_equal 7, rows.size
    assert_equal Array.new(7, @code), rows.map { |row| row.fetch("sku_code") }
    assert rows.all? { |row| row.fetch("on_hand_quantity").blank? }
  end

  test "week switching reads only the selected week and generation uses that week despite SKU filters" do
    @excluded_sku = Ec::Sku.create!(sku_code: "#{@code}-NO-ALLOCATION")
    Ec::OwnWarehouseSkuCostAllocation.create!(sku: @sku, own_warehouse_code: @code,
      week_start: @week, week_end: @week + 6, storage_cost: 100, total_cost: 100)
    Ec::OwnWarehouseSkuCostAllocation.create!(sku: @sku, own_warehouse_code: @code,
      week_start: @week + 7, week_end: @week + 13, storage_cost: 200, total_cost: 200)

    [@week, @week + 7, @week - 7].each do |week|
      assert_no_difference "Ec::OwnWarehouseSkuCostAllocation.count" do
        get own_warehouse_costs_path(format: :json), params: {
          tab: "allocations", from_date: week, to_date: week + 6, own_warehouse_code: @code,
          developer_id: -1, operator_id: -1
        }
      end
      assert_response :success
      payload = JSON.parse(response.body)
      expected = week == @week - 7 ? [] : [week.to_s]
      assert_equal expected, payload["rows"].map { |row| row["week_start"] }
      assert_equal(week == @week ? 100 : week == @week + 7 ? 200 : 0, payload["total_cost"].to_d)

      get own_warehouse_costs_path, params: { tab: "allocations", from_date: week, to_date: week + 6,
        own_warehouse_code: @code, sku_codes: [@excluded_sku.sku_code] }, headers: { "Accept" => "text/html" }
      assert_response :success
      assert_select ".own-warehouse-table tbody .code-text", count: 0
      assert_select ".page-h form[action=?]", calculate_own_warehouse_costs_path do
        assert_select "input[name='week_start'][value=?]", week.to_s
        assert_select "input[name='own_warehouse_code'][value=?]", @code
        assert_select "button", text: I18n.t(week == @week - 7 ? "own_warehouse.generate_week" : "own_warehouse.regenerate_week")
      end
    end
  end

  test "invalid ranges retain filters and prompt without querying allocations or showing generation" do
    current_week = Date.current.beginning_of_week(:monday)
    ranges = [[@week + 1, @week + 6], [@week + 1, @week + 7], [@week, @week + 13],
      [@week + 7, @week + 6], [current_week, current_week + 6]]
    ranges.each do |from, to|
      queries = []
      callback = ->(event) { queries << event.payload[:sql] }
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
        get own_warehouse_costs_path, params: { tab: "allocations", from_date: from, to_date: to,
          own_warehouse_code: @code }, headers: { "Accept" => "text/html" }
      end
      assert_response :success
      assert_select "[data-controller='time-range-selector']", count: 1
      assert_select "input[name='from_date'][value=?]", from.to_s
      assert_select "input[name='to_date'][value=?]", to.to_s
      assert_select ".own-warehouse-range-warning", text: I18n.t("own_warehouse.errors.invalid_week")
      assert_select ".own-warehouse-table, .own-warehouse-rate-panel, .product-summary-grid", count: 0
      assert_select "form[action=?]", calculate_own_warehouse_costs_path, count: 0
      assert_empty queries.grep(/FROM "ec_own_warehouse_sku_cost_allocations"/)
    end

    get own_warehouse_sku_costs_path(format: :json), params: {
      from_date: @week, to_date: @week + 13, own_warehouse_code: @code
    }
    assert_response :unprocessable_entity
    assert_equal [], JSON.parse(response.body)["rows"]
    assert_equal I18n.t("own_warehouse.errors.invalid_week"), JSON.parse(response.body)["error"]
  end

  test "system POST publishes with excluded SKUs and repeats idempotently" do
    create_system_snapshots
    @system_period = Ec::OwnWarehouseCostPeriod.create!(period_params.merge(
      own_warehouse_code: "BY", storage_ratio: 1, transport_ratio: 0, labor_ratio: 0
    ))
    @system_period.confirm!(actor: @user)

    post calculate_own_warehouse_costs_path(format: :json), params: system_params
    assert_response :success
    payload = JSON.parse(response.body)
    assert payload["success"]
    assert_operator payload["excluded_sku_count"], :>=, 1
    assert_operator payload["issue_counts"].fetch("excluded_sku"), :>=, 1
    allocation = Ec::OwnWarehouseSkuCostAllocation.find_by!(sku: @sku, own_warehouse_cost_period: @system_period)
    assert_equal 700.to_d, allocation.total_cost
    assert_includes allocation.calculation_inputs.dig("source_metadata", "excluded_skus"), @excluded_sku.sku_code
    assert_not Ec::OwnWarehouseSkuCostAllocation.where(sku: @excluded_sku, week_start: @week).exists?

    assert_no_difference "Ec::OwnWarehouseSkuCostAllocation.count" do
      post calculate_own_warehouse_costs_path, params: system_params, headers: { "Accept" => "text/html" }
    end
    assert_redirected_to own_warehouse_costs_path(tab: "allocations", from_date: @week, to_date: @week + 6, own_warehouse_code: "BY")
    assert_match(/1|excluded|排除|исключ/, flash[:notice])
    get response.location, headers: { "Accept" => "text/html" }
    assert_response :success
    assert_select ".own-warehouse-input-warning", count: 1
    assert_select ".error-box", count: 0
    assert_select ".page-h form[action=?] button", calculate_own_warehouse_costs_path, text: I18n.t("own_warehouse.regenerate_week")
  end

  test "system errors report missing configuration rather than excluded SKU issues" do
    create_system_snapshots
    post calculate_own_warehouse_costs_path(format: :json), params: system_params
    assert_response :unprocessable_entity
    assert_equal I18n.t("own_warehouse.errors.missing_version"), JSON.parse(response.body)["error"]
    assert_not Ec::OwnWarehouseSkuCostAllocation.where(sku: @sku, week_start: @week).exists?

    post calculate_own_warehouse_costs_path, params: system_params, headers: { "Accept" => "text/html" }
    assert_redirected_to own_warehouse_costs_path(tab: "allocations", from_date: @week, to_date: @week + 6, own_warehouse_code: "BY")
    assert_equal I18n.t("own_warehouse.errors.missing_version"), flash[:alert]
  end

  test "system POST explains when no eligible SKUs remain" do
    post calculate_own_warehouse_costs_path(format: :json), params: system_params
    assert_response :unprocessable_entity
    assert_equal I18n.t("own_warehouse.errors.no_eligible_inputs"), JSON.parse(response.body)["error"]
  end

  test "restricted user cannot inspect or mutate financial configuration and sees assigned SKU only" do
    UserRole.where(user_id: @user.id).delete_all
    @user.roles << Role.find_by!(code: "sku_manager")
    @user.reload
    get own_warehouse_costs_path(format: :json)
    assert_response :forbidden
    post calculate_own_warehouse_sku_costs_path(format: :json)
    assert_response :forbidden
    Ec::OwnWarehouseSkuCostAllocation.create!(sku: @sku, own_warehouse_code: @code, week_start: @week, week_end: @week + 6)
    get own_warehouse_sku_costs_path(format: :json), params: { from_date: @week, to_date: @week + 6, own_warehouse_code: @code, sku_codes: [@code] }
    assert_response :success
    assert_equal 0, JSON.parse(response.body)["rows"].size
    Ec::SkuDeveloperAssignment.create!(sku_code: @code, user: @user)
    get own_warehouse_sku_costs_path(format: :json), params: { from_date: @week, to_date: @week + 6, own_warehouse_code: @code }
    assert_equal 1, JSON.parse(response.body)["rows"].size
    get own_warehouse_sku_costs_path, params: { from_date: @week, to_date: @week + 6, own_warehouse_code: @code }, headers: { "Accept" => "text/html" }
    assert_response :success
    assert_select "form[action=?]", calculate_own_warehouse_costs_path, count: 0
  end

  %i[get post patch].each do |verb|
    define_method(verb) do |path, **options|
      sign_in @user
      super(path, **options)
    end
  end

  private

  def system_params
    { source: "system", week_start: @week, own_warehouse_code: "BY" }
  end

  def create_system_snapshots
    @excluded_sku = Ec::Sku.create!(sku_code: "#{@code}-EXCLUDED")
    7.times do |day|
      Ec::Snapshot.create!(sku: @sku, snapshot_type: "inventory", snapshot_date: @week + day,
        content: { overview: { available_stock: 100, unit_volume_l: 10 } })
    end
  end

  def period_params
    { own_warehouse_code: @code, effective_from: @week, effective_to: @week + 6, total_operating_cost: 700, storage_ratio: 0.4, transport_ratio: 0.25, labor_ratio: 0.35, fbo_labor_weight: 0.1 }
  end
end
