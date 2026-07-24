require "test_helper"

class ErpAI::SkusControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(4)
    @user = create_user_with_roles("ai-sku-overview-#{@token}@example.com", "manager")
    @raw_api_token, = UserApiKey.generate_for!(@user, name: "SKU Overview Agent")
    @operator = User.create!(
      email: "ai-sku-operator-#{@token}@example.com",
      password: "password123",
      password_confirmation: "password123",
      name: "SKU 运营 #{@token}"
    )
    @developer = User.create!(
      email: "ai-sku-developer-#{@token}@example.com",
      password: "password123",
      password_confirmation: "password123",
      name: "SKU 开发 #{@token}"
    )
    @category = Ec::SkuCategory.create!(
      code: "AI-SKU-CATEGORY-#{@token.upcase}",
      name: "AI SKU 类目 #{@token}"
    )
    @master_sku = Ec::MasterSku.create!(
      master_sku_code: "AI-SKU-SPU-#{@token.upcase}",
      product_name: "AI SKU SPU #{@token}"
    )
    @sku = Ec::Sku.create!(
      sku_code: "AI-SKU-OVERVIEW-#{@token.upcase}",
      product_name: "AI SKU 基础信息 #{@token}",
      master_sku: @master_sku,
      sku_category: @category,
      is_active: true
    )
    @sku.marketing_states.create!(
      grade: "A",
      stage: "grw",
      effective_at: 1.day.ago,
      changed_by: @user
    )
    Ec::SkuDeveloperAssignment.create!(sku: @sku, user: @developer)
    @store = Ec::Store.create!(
      platform: "ozon",
      store_name: "AI SKU 店铺 #{@token}",
      company_type: "general",
      is_active: true
    )
    @sku_product = Ec::SkuProduct.create!(
      sku_code: @sku.sku_code,
      store: @store,
      product_id: "AI-SKU-PRODUCT-#{@token.upcase}",
      platform_sku_id: "AI-SKU-PLATFORM-#{@token.upcase}"
    )
    Ec::SkuProductOperator.create!(sku_product: @sku_product, user: @operator)
  end

  teardown do
    Ec::SkuProductOperator.where(sku_product_id: @sku_product&.id).delete_all
    Ec::SkuProduct.where(id: @sku_product&.id).delete_all
    Ec::Store.where(id: @store&.id).delete_all
    Ec::SkuMarketingState.where(sku_id: @sku&.id).delete_all
    Ec::SkuDeveloperAssignment.where(sku_code: @sku&.sku_code).delete_all
    Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
    Ec::MasterSku.where(id: @master_sku&.id).delete_all
    Ec::SkuCategory.where(id: @category&.id).delete_all
    UserApiKey.where(user: @user).delete_all
    user_ids = [@user&.id, @operator&.id, @developer&.id].compact
    UserRole.where(user_id: user_ids).delete_all
    User.where(id: user_ids).delete_all
  end

  test "returns sku overview" do
    get "/ai/skus/overview",
      params: { sku: @sku.sku_code.downcase },
      headers: bearer_headers(@raw_api_token)

    assert_response :success
    body = response.parsed_body
    assert_equal({
      "sku" => @sku.sku_code,
      "name" => @sku.product_name,
      "marketing_grade" => "A",
      "marketing_stage" => "grw",
      "marketing_strategy" => "加速成长",
      "developers" => [@developer.display_name],
      "operators" => [@operator.display_name],
      "category" => @category.name,
      "spu" => @master_sku.master_sku_code,
      "is_active" => true
    }, body.fetch("data"))
    assert_match "SKU基础信息", body.fetch("description")
  end

  test "requires api key" do
    get "/ai/skus/overview", params: { sku: @sku.sku_code }

    assert_response :unauthorized
    assert_equal({ "error" => "Unauthorized" }, response.parsed_body)
  end

  test "returns not found for unknown sku" do
    get "/ai/skus/overview",
      params: { sku: "MISSING-#{@token}" },
      headers: bearer_headers(@raw_api_token)

    assert_response :not_found
    assert_equal({ "error" => "SKU not found" }, response.parsed_body)
  end

  test "requires sku parameter" do
    get "/ai/skus/overview", headers: bearer_headers(@raw_api_token)

    assert_response :bad_request
    assert_equal({ "error" => "sku is required" }, response.parsed_body)
  end

  private

  def bearer_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end
end
