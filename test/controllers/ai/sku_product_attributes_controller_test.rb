require "test_helper"

class ErpAI::SkuProductAttributesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(6).upcase
    @user = create_user_with_roles("ai-product-attributes-#{@token}@example.com", "manager")
    @raw_api_token, = UserApiKey.generate_for!(@user, name: "SKU product attributes")
    @sku = Ec::Sku.create!(sku_code: "AI-ATTR-#{@token}", product_info: "Baseline information")
  end

  teardown do
    Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
    UserApiKey.where(user_id: @user&.id).delete_all
    UserRole.where(user_id: @user&.id).delete_all
    User.where(id: @user&.id).delete_all
  end

  test "returns the read-only product response through the json endpoint" do
    get "/ai/sku_product_attributes.json",
      params: { sku_code: @sku.sku_code.downcase },
      headers: bearer_headers

    assert_response :success
    assert_equal true, response.parsed_body.fetch("success")
    assert_equal @sku.sku_code, response.parsed_body.dig("sku", "sku_code")
    assert_equal "Baseline information", response.parsed_body.dig("sku", "product_info")
    assert_equal [], response.parsed_body.fetch("listings")
    refute response.parsed_body.key?("pagination")
  end

  test "requires authentication" do
    get "/ai/sku_product_attributes.json", params: { sku_code: @sku.sku_code }

    assert_response :unauthorized
  end

  test "rejects a blank SKU code" do
    [ nil, "   " ].each do |sku_code|
      get "/ai/sku_product_attributes.json", params: { sku_code: }, headers: bearer_headers

      assert_response :bad_request
      assert_equal "sku_code_required", response.parsed_body.dig("error", "code")
    end
  end

  test "rejects invalid pagination parameters" do
    [ { limit: 0 }, { limit: 501 }, { limit: "1.5" }, { offset: -1 }, { offset: "bad" } ].each do |pagination|
      get "/ai/sku_product_attributes.json",
        params: { sku_code: @sku.sku_code, **pagination },
        headers: bearer_headers

      assert_response :bad_request
    end
  end

  test "returns sku_not_found for missing and soft-deleted SKUs" do
    missing_code = "MISSING-#{@token}"
    @sku.destroy!

    [ missing_code, @sku.sku_code ].each do |sku_code|
      get "/ai/sku_product_attributes.json", params: { sku_code: }, headers: bearer_headers

      assert_response :not_found
      assert_equal "sku_not_found", response.parsed_body.dig("error", "code")
    end
  end

  private

  def bearer_headers
    { "Authorization" => "Bearer #{@raw_api_token}" }
  end
end
