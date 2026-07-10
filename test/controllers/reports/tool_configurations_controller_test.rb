require "test_helper"

class ReportsToolConfigurationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(4).upcase
    @current_user = create_user_with_roles("tool-config-current-#{@token.downcase}@example.com", "auditor")
    @other_user = create_user_with_roles("tool-config-other-#{@token.downcase}@example.com", "auditor")
    sign_in @current_user

    @definition = Ec::ToolDefinition.create!(
      tool_type: "wb_pallet_optimizer_#{@token}",
      version: 1,
      name: "WB Pallet #{@token}",
      slug: "wb-pallet-#{@token.downcase}",
      renderer_key: "wb_pallet_optimizer_v1",
      created_by: @current_user
    )
  end

  teardown do
    Ec::ToolConfiguration.where("name LIKE ?", "%#{@token}%").delete_all if defined?(Ec::ToolConfiguration)
    Ec::ToolDefinition.where("tool_type LIKE ?", "%#{@token}%").delete_all if defined?(Ec::ToolDefinition)
    UserRole.joins(:user).where("users.email LIKE ?", "%#{@token.downcase}@example.com").delete_all
    User.where("email LIKE ?", "%#{@token.downcase}@example.com").delete_all
  end

  test "create persists a configuration for the current user" do
    assert_difference "Ec::ToolConfiguration.count", 1 do
      post "/reports/tool_configurations",
        params: {
          ec_tool_configuration: {
            tool_definition_id: @definition.id,
            name: "WB Config #{@token}",
            config_json: { exchange: "12", sku_name: "Plan #{@token}" },
            active: "1"
          }
        },
        as: :json
    end

    configuration = Ec::ToolConfiguration.find_by!(name: "WB Config #{@token}")
    assert_response :success
    assert_equal @current_user.id, configuration.created_by_id
    assert_equal "12", configuration.config_json["exchange"]
  end

  test "owner can update a configuration" do
    configuration = Ec::ToolConfiguration.create!(
      tool_definition: @definition,
      name: "WB Config #{@token}",
      config_json: { "exchange" => "12" },
      created_by: @current_user
    )

    patch "/reports/tool_configurations/#{configuration.id}",
      params: {
        ec_tool_configuration: {
          name: "WB Config Updated #{@token}",
          config_json: { exchange: "13" },
          active: "0"
        }
      },
      as: :json

    assert_response :success
    configuration.reload
    assert_equal "WB Config Updated #{@token}", configuration.name
    assert_equal "13", configuration.config_json["exchange"]
    assert_not configuration.active
  end

  test "non owner cannot update a configuration" do
    configuration = Ec::ToolConfiguration.create!(
      tool_definition: @definition,
      name: "WB Config #{@token}",
      config_json: { "exchange" => "12" },
      created_by: @other_user
    )

    patch "/reports/tool_configurations/#{configuration.id}",
      params: {
        ec_tool_configuration: {
          name: "WB Config Updated #{@token}"
        }
      },
      as: :json

    assert_response :forbidden
    configuration.reload
    assert_equal "WB Config #{@token}", configuration.name
  end

  test "owner can destroy a configuration and returns to tools list" do
    configuration = Ec::ToolConfiguration.create!(
      tool_definition: @definition,
      name: "WB Config #{@token}",
      config_json: { "exchange" => "12" },
      created_by: @current_user
    )

    assert_difference "Ec::ToolConfiguration.count", -1 do
      delete "/reports/tool_configurations/#{configuration.id}",
        params: {
          return_to: "/reports/tools?q=WB+Config+#{@token}&tool_type=#{@definition.tool_type}"
        }
    end

    assert_redirected_to "/reports/tools?q=WB+Config+#{@token}&tool_type=#{@definition.tool_type}"
    assert_nil Ec::ToolConfiguration.find_by(id: configuration.id)
  end

  test "non owner cannot destroy a configuration" do
    configuration = Ec::ToolConfiguration.create!(
      tool_definition: @definition,
      name: "WB Config #{@token}",
      config_json: { "exchange" => "12" },
      created_by: @other_user
    )

    assert_no_difference "Ec::ToolConfiguration.count" do
      delete "/reports/tool_configurations/#{configuration.id}"
    end

    assert_response :forbidden
    assert Ec::ToolConfiguration.exists?(configuration.id)
  end

  test "show exposes overwrite and save as actions based on ownership" do
    own_configuration = Ec::ToolConfiguration.create!(
      tool_definition: @definition,
      name: "WB Config Own #{@token}",
      config_json: { "exchange" => "12" },
      created_by: @current_user
    )
    other_configuration = Ec::ToolConfiguration.create!(
      tool_definition: @definition,
      name: "WB Config Other #{@token}",
      config_json: { "exchange" => "12" },
      created_by: @other_user
    )

    get "/reports/tool_configurations/#{own_configuration.id}", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select ".inventory-drawer[data-close-path='/reports/tools']"
    assert_select ".inventory-drawer__header button", "覆盖保存"
    assert_select ".inventory-drawer__header button", "另存为"
    assert_select "[data-tool-save-name-modal]", count: 1

    sign_in @current_user
    get "/reports/tool_configurations/#{other_configuration.id}", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select ".inventory-drawer__header button", text: "覆盖保存", count: 0
    assert_select ".inventory-drawer__header button", "另存为"
  end
end
