require "test_helper"

class Ec::ToolDefinitionTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(4).upcase
    @user = User.create!(
      email: "tool-definition-#{@token.downcase}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
  end

  teardown do
    Ec::ToolConfiguration.where("name LIKE ?", "%#{@token}%").delete_all if defined?(Ec::ToolConfiguration)
    Ec::ToolDefinition.where("tool_type LIKE ?", "%#{@token}%").delete_all if defined?(Ec::ToolDefinition)
    User.where(id: @user.id).delete_all if @user
  end

  test "requires a unique version within a tool type" do
    Ec::ToolDefinition.create!(
      tool_type: "wb_pallet_optimizer_#{@token}",
      version: 1,
      name: "WB Pallet #{@token}",
      slug: "wb-pallet-#{@token.downcase}",
      renderer_key: "wb_pallet_optimizer_v1",
      created_by: @user
    )

    duplicate = Ec::ToolDefinition.new(
      tool_type: "wb_pallet_optimizer_#{@token}",
      version: 1,
      name: "WB Pallet Duplicate #{@token}",
      slug: "wb-pallet-duplicate-#{@token.downcase}",
      renderer_key: "wb_pallet_optimizer_v1",
      created_by: @user
    )

    assert_not duplicate.valid?
    assert duplicate.errors.of_kind?(:version, :taken)
  end

  test "returns the latest active version for a tool type" do
    inactive = Ec::ToolDefinition.create!(
      tool_type: "wb_pallet_optimizer_#{@token}",
      version: 1,
      name: "WB Pallet Old #{@token}",
      slug: "wb-pallet-old-#{@token.downcase}",
      renderer_key: "wb_pallet_optimizer_v1",
      active: false,
      created_by: @user
    )
    active = Ec::ToolDefinition.create!(
      tool_type: "wb_pallet_optimizer_#{@token}",
      version: 2,
      name: "WB Pallet New #{@token}",
      slug: "wb-pallet-new-#{@token.downcase}",
      renderer_key: "wb_pallet_optimizer_v1",
      active: true,
      created_by: @user
    )

    assert_equal active, Ec::ToolDefinition.latest_active_for("wb_pallet_optimizer_#{@token}")
    assert_not_equal inactive, Ec::ToolDefinition.latest_active_for("wb_pallet_optimizer_#{@token}")
  end
end
