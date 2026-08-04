require "test_helper"

class ErpAI::SupplyOrderReportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(4)
    @user = create_user_with_roles("ai-supply-orders-#{@token}@example.com", "manager")
    @raw_api_token, = UserApiKey.generate_for!(@user, name: "Supply Order Agent")
  end

  teardown do
    UserApiKey.where(user: @user).delete_all
    UserRole.where(user: @user).delete_all
    User.where(id: @user.id).delete_all
  end

  test "requires an api key with report permission" do
    post "/ai/supply_order_reports.json", params: { store_ref: "wb:1" }

    assert_response :unauthorized
  end

  test "returns the shared supply report with one hundred rows per page" do
    report = {
      meta: { platform: "wb", store_ref: "wb:1", store_name: "WB Store", columns: [:supply_id] },
      rows: [{ supply_id: "SUPPLY-1" }],
      pagination: { page: 1, per_page: 100, total_count: 1, total_pages: 1 }
    }
    received_params = nil
    received_per_page = nil
    query = Object.new
    query.define_singleton_method(:call) { report }
    query_class = SupplyOrderReports::ReportQuery
    original_new = query_class.method(:new)
    query_class.define_singleton_method(:new) do |params:, per_page:|
      received_params = params
      received_per_page = per_page
      query
    end

    post "/ai/supply_order_reports.json",
      params: {
        store_ref: "wb:1",
        master_sku_ids: [12],
        sku_codes: ["SKU-1"],
        operator_id: 34,
        statuses: ["4"],
        page: 2
      },
      headers: bearer_headers(@raw_api_token)

    assert_response :success
    assert_equal 100, received_per_page
    assert_equal "wb:1", received_params[:store_ref]
    assert_equal ["12"], received_params[:master_sku_ids]
    assert_equal ["SKU-1"], received_params[:sku_codes]
    assert_equal "34", received_params[:operator_id]
    assert_equal ["4"], received_params[:statuses]
    assert_equal "2", received_params[:page]

    body = response.parsed_body
    assert_equal true, body.fetch("success")
    assert_equal "ok", body.fetch("message")
    assert_equal "wb", body.dig("data", "meta", "platform")
    assert_equal 100, body.dig("data", "pagination", "per_page")
  ensure
    query_class&.define_singleton_method(:new, original_new) if original_new
  end

  test "returns bad request when store is missing" do
    post "/ai/supply_order_reports.json", headers: bearer_headers(@raw_api_token)

    assert_response :bad_request
    assert_equal false, response.parsed_body.fetch("success")
    assert_match "store_ref", response.parsed_body.fetch("message")
  end

  test "returns bad request for an invalid store reference" do
    post "/ai/supply_order_reports.json",
      params: { store_ref: "amazon:1" },
      headers: bearer_headers(@raw_api_token)

    assert_response :bad_request
    assert_equal I18n.t("supply_order_reports.errors.invalid_store_ref"), response.parsed_body.fetch("message")
  end

  test "returns not found for an inactive or missing account" do
    post "/ai/supply_order_reports.json",
      params: { store_ref: "wb:999999999" },
      headers: bearer_headers(@raw_api_token)

    assert_response :not_found
    assert_equal I18n.t("supply_order_reports.errors.store_not_found"), response.parsed_body.fetch("message")
  end

  private

  def bearer_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end
end
