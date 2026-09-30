require "test_helper"

class ErpAI::SkuContextToolTest < ActiveSupport::TestCase
  class FakeRequestClient
    class << self
      attr_accessor :arguments
    end

    def initialize(current_user:)
      @current_user = current_user
    end

    def call(arguments)
      self.class.arguments = arguments
      {
        success: true,
        body: "# SKU context\n\n## base\n\n- **sku_code:** SKU-CONTEXT"
      }
    end
  end

  setup do
    @user = User.create!(
      email: "sku-context-tool-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
    @user.roles << Role.find_by!(code: "super_admin")
    @sku = Ec::Sku.create!(sku_code: "SKU-CONTEXT-#{SecureRandom.hex(4)}")
  end

  teardown do
    Ec::Sku.where(id: @sku&.id).delete_all
    UserRole.where(user_id: @user&.id).delete_all
    User.where(id: @user&.id).delete_all
    FakeRequestClient.arguments = nil
  end

  test "fetches only the requested module and returns its description and markdown" do
    result = ErpAI::SkuContextTool.new(
      current_user: @user,
      request_client: FakeRequestClient
    ).call("sku_code" => @sku.sku_code.downcase, "module" => "base")

    assert_equal @sku.sku_code, result.fetch(:sku_code)
    assert_equal "base", result.fetch(:module)
    assert result.fetch(:description).present?
    assert_equal "# SKU context\n\n## base\n\n- **sku_code:** SKU-CONTEXT", result.fetch(:markdown)
    assert_equal "/ai/v3/sku/base_context", FakeRequestClient.arguments.fetch("url")
    assert_equal({ "sku_code" => @sku.sku_code }, FakeRequestClient.arguments.fetch("params"))
    assert_equal({ "Accept" => "text/markdown" }, FakeRequestClient.arguments.fetch("headers"))
  end

  test "rejects an unsupported module before making a request" do
    result = ErpAI::SkuContextTool.new(
      current_user: @user,
      request_client: FakeRequestClient
    ).call("sku_code" => @sku.sku_code, "module" => "full")

    assert_equal "module is invalid", result.fetch(:error)
    assert_nil FakeRequestClient.arguments
  end
end
