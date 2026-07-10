require "test_helper"

class Ec::ToolConfigurationTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(4).upcase
    @user = User.create!(
      email: "tool-config-#{@token.downcase}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
    @definition = Ec::ToolDefinition.create!(
      tool_type: "wb_pallet_optimizer_#{@token}",
      version: 1,
      name: "WB Pallet #{@token}",
      slug: "wb-pallet-#{@token.downcase}",
      renderer_key: "wb_pallet_optimizer_v1",
      created_by: @user
    )
  end

  teardown do
    Ec::ToolConfiguration.where("name LIKE ?", "%#{@token}%").delete_all if defined?(Ec::ToolConfiguration)
    Ec::ToolDefinition.where("tool_type LIKE ?", "%#{@token}%").delete_all if defined?(Ec::ToolDefinition)
    User.where(id: @user.id).delete_all if @user
  end

  test "belongs to a tool definition and creator" do
    configuration = Ec::ToolConfiguration.create!(
      tool_definition: @definition,
      name: "WB Config #{@token}",
      config_json: { "exchange" => "12" },
      created_by: @user
    )

    assert_equal @definition, configuration.tool_definition
    assert_equal @user, configuration.created_by
    assert_equal "12", configuration.config_json["exchange"]
  end

  test "requires a name" do
    configuration = Ec::ToolConfiguration.new(
      tool_definition: @definition,
      name: "",
      config_json: {},
      created_by: @user
    )

    assert_not configuration.valid?
    assert configuration.errors.of_kind?(:name, :blank)
  end
end
