require "test_helper"

class SkuScenarioVisibilityControllerTest < ActionDispatch::IntegrationTest
  IDENTITY = { platform: "wb", market: "ru", delivery_mode: "fbo", warehouse_region: "main", company_type: "small" }.freeze
  KEY = "wb|ru|fbo|main|small".freeze

  setup do
    token = SecureRandom.hex(5)
    @user = create_user_with_roles("scenario-vis-#{token}@example.com", "manager")
    sign_in @user
    @sku = Ec::Sku.create!(sku_code: "SV-#{token.upcase}", product_name: "Scenario visibility", is_active: true)
    Ec::SkuOperatorAssignment.create!(sku: @sku, user: @user)
    @extra_users = []
  end

  teardown do
    visibility_ids = Ec::SkuScenarioVisibility.where(sku_id: @sku&.id).pluck(:id)
    version_ids = Ec::SkuProfitVersion.where(sku_id: @sku&.id).pluck(:id)
    context_ids = Ec::SkuProfitVersionContext.where(sku_profit_version_id: version_ids).pluck(:id)
    Ec::OperationLog.where(record_type: "Ec::SkuScenarioVisibility", record_id: visibility_ids).delete_all
    Ec::OperationLog.where(record_type: "Ec::SkuProfitVersionContext", record_id: context_ids).delete_all
    Ec::OperationLog.where(record_type: "Ec::SkuProfitVersion", record_id: version_ids).delete_all
    Ec::OperationLog.where(record_type: "Ec::Sku", record_id: @sku&.id).delete_all
    Ec::SkuScenarioVisibility.where(id: visibility_ids).delete_all
    Ec::SkuProfitVersionContext.where(id: context_ids).delete_all
    Ec::SkuProfitVersion.where(id: version_ids).delete_all
    Ec::SkuOperatorAssignment.where(sku_code: @sku&.sku_code).delete_all
    Ec::Sku.where(id: @sku&.id).delete_all
    user_ids = [ @user&.id, *@extra_users.map(&:id) ].compact
    UserRole.where(user_id: user_ids).delete_all
    User.where(id: user_ids).delete_all
  end

  test "hides and restores a scenario and logs who did it" do
    patch report_sku_scenario_visibility_path(@sku.sku_code), params: IDENTITY.merge(hidden: true), as: :json

    assert_response :success
    assert_equal({ "key" => KEY, "hidden" => true }, response.parsed_body)
    assert_equal Set[KEY], Ec::SkuScenarioVisibility.hidden_keys_for(@sku)
    record = Ec::SkuScenarioVisibility.find_by!(sku_id: @sku.id)
    assert_equal @user.id, record.updated_by_id
    assert Ec::OperationLog.where(record_type: "Ec::SkuScenarioVisibility", record_id: record.id).exists?

    sign_in @user
    patch report_sku_scenario_visibility_path(@sku.sku_code), params: IDENTITY.merge(hidden: false), as: :json

    assert_response :success
    assert_equal false, response.parsed_body.fetch("hidden")
    assert_empty Ec::SkuScenarioVisibility.hidden_keys_for(@sku)
  end

  test "an unknown scenario is refused" do
    patch report_sku_scenario_visibility_path(@sku.sku_code), params: IDENTITY.merge(market: "kz", hidden: true), as: :json

    assert_response :unprocessable_entity
    assert_empty Ec::SkuScenarioVisibility.where(sku_id: @sku.id)
  end

  test "an operator cannot change an SKU that is not theirs" do
    other = create_user_with_roles("scenario-vis-other-#{SecureRandom.hex(4)}@example.com", "manager")
    @extra_users << other
    sign_in other

    patch report_sku_scenario_visibility_path(@sku.sku_code), params: IDENTITY.merge(hidden: true), as: :json

    assert_response :not_found
    assert_empty Ec::SkuScenarioVisibility.where(sku_id: @sku.id)
  end

  test "a reader without the manage SKUs permission is refused" do
    reader = create_user_with_roles("scenario-vis-reader-#{SecureRandom.hex(4)}@example.com", "auditor")
    @extra_users << reader
    sign_in reader

    patch report_sku_scenario_visibility_path(@sku.sku_code), params: IDENTITY.merge(hidden: true), as: :json

    assert_response :forbidden
    assert_empty Ec::SkuScenarioVisibility.where(sku_id: @sku.id)
  end

  test "a super admin may change any SKU" do
    admin = create_user_with_roles("scenario-vis-admin-#{SecureRandom.hex(4)}@example.com", "super_admin")
    @extra_users << admin
    sign_in admin

    patch report_sku_scenario_visibility_path(@sku.sku_code), params: IDENTITY.merge(hidden: true), as: :json

    assert_response :success
    assert_equal Set[KEY], Ec::SkuScenarioVisibility.hidden_keys_for(@sku)
  end

  test "the workbench page marks hidden scenarios and leaves them out of the incomplete count" do
    Ec::SkuScenarioVisibility.set!(sku: @sku, identity: IDENTITY.stringify_keys, hidden: true, user: @user)

    get report_sku_path(@sku.sku_code), params: { tab: "profit_prediction", locale: "en" }

    assert_response :success
    assert_select "tr[data-scenario-key='#{KEY}'][data-scenario-hidden='true'][hidden]"
    assert_select "tr[data-scenario-key='wb|ru|fbo|main|general'][data-scenario-hidden='false']:not([hidden])"
    assert_select "[data-profit-prediction-target='scenarioBanner'][hidden]"
    state = JSON.parse(css_select(".profit-prediction-workbench").first["data-profit-prediction-scenario-state-value"])
    assert_equal Ec::SkuProfitStandardContexts::SCENARIOS.size, state.fetch("scenarios").size
    assert_equal [ KEY ], state.fetch("scenarios").select { |scenario| scenario["hidden"] }.map { |scenario| scenario["key"] }
    assert_equal Ec::SkuScenarioSales::MIN_UNITS, state.fetch("min_units")
    assert_equal report_sku_scenario_visibility_path(@sku.sku_code),
      css_select(".profit-prediction-workbench").first["data-profit-prediction-scenario-visibility-url-value"]
  end

  test "a new SKU shows every scenario" do
    get report_sku_path(@sku.sku_code), params: { tab: "profit_prediction", locale: "en" }

    assert_response :success
    assert_select "tr[data-scenario-key][data-scenario-hidden='true']", count: 0
    assert_select "tr[data-scenario-key]", count: Ec::SkuProfitStandardContexts::SCENARIOS.size
  end

  test "the mark says one thing for no sales and another for thin sales" do
    get report_sku_path(@sku.sku_code), params: { tab: "profit_prediction", locale: "en" }

    messages = JSON.parse(css_select(".profit-prediction-workbench").first["data-profit-prediction-messages-value"]).fetch("scenarios")
    assert_match(/Nothing signed/, messages.fetch("warning_none"))
    assert_match(/Only __UNITS__ units/, messages.fetch("warning"))
    assert_no_match(/__UNITS__/, messages.fetch("warning_none"))
  end
end
