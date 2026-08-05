require "test_helper"

class Reports::SupplyOrdersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(5).upcase
    @user = create_user_with_roles("supply-ui-#{@token.downcase}@example.com", "manager")
    sign_in @user
    @account = RawWb::SellerAccount.create!(name: "Supply UI #{@token}", api_token: "ui-#{@token}", is_active: true, company_type: :small)
    @supply = RawWb::Supply.create!(account: @account, wb_supply_id: "WB-UI-#{@token}", preorder_id: 98765, status_id: 5, box_type_id: 2, synced_at: Time.current)
    RawWb::SupplyItem.create!(account: @account, wb_supply_id: @supply.wb_supply_id, nm_id: 7654321, quantity: 10, accepted_qty: 10, synced_at: Time.current)
  end

  teardown do
    RawWb::SupplyItem.where(account_id: @account.id).delete_all
    RawWb::Supply.where(account_id: @account.id).delete_all
    @account.destroy!
    UserRole.where(user_id: @user.id).delete_all
    @user.destroy!
  end

  test "renders item-level WB supply rows and platform-specific columns" do
    get reports_supply_orders_path, params: { store_ref: "wb:#{@account.id}" }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", "送仓记录"
    assert_select "form[action=?][data-turbo-frame='supply_order_report_results']", reports_supply_orders_path
    assert_select "a.weekly-profit-filter-tag.is-active", text: "WB · Supply UI #{@token}"
    assert_select "turbo-frame#supply_order_report_results"
    assert_select "th", "WB 商品 ID"
    assert_select "th", "实收数量"
    assert_select "#supply-order-status-filter-trigger", text: /全部状态/
    assert_select "#supply-order-responsible-user-filter-operator-trigger", text: /全部运营人员/
    assert_select "td", @supply.wb_supply_id
    assert_select "td", "7654321"
    assert_select "td", "已接收"
    assert_select "td", "箱装"
  end

  test "returns the flattened report as JSON" do
    get reports_supply_orders_path(format: :json), params: { store_ref: "wb:#{@account.id}" }
    assert_response :success
    assert_equal @supply.wb_supply_id, response.parsed_body.dig("data", "rows", 0, "supply_id")
  end

  test "renders the selected operator and preserves it in store links" do
    get reports_supply_orders_path, params: { store_ref: "wb:#{@account.id}", operator_id: @user.id }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "#supply-order-responsible-user-filter-operator-trigger", text: @user.display_name
    assert_select "a.weekly-profit-filter-tag[href*='operator_id=#{@user.id}']", minimum: 1
  end

  test "renders selected statuses in the global multiselect and clears them from cross-platform store links" do
    ozon_account = RawOzon::SellerAccount.create!(company_name: "Supply Ozon UI #{@token}", client_id: "ozon-ui-#{@token}", api_key: "key-#{@token}", is_active: true, company_type: :small)
    get reports_supply_orders_path, params: { store_ref: "wb:#{@account.id}", statuses: ["5"] }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "[data-controller='popover-multiselect-filter'] input[type='checkbox'][name='statuses[]'][value='5'][checked]"
    assert_select "#supply-order-status-filter-trigger", text: /已接收/
    assert_select "a[href*='store_ref=ozon%3A#{ozon_account.id}'][href*='statuses']", count: 0
  ensure
    ozon_account&.destroy!
  end
end
