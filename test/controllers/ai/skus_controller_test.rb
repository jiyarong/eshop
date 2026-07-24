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
    }, body.fetch("data").except("marketing_state_history"))
    assert_match "SKU基础信息", body.fetch("description")
  end

  test "returns marketing grade and stage history in reverse chronological order" do
    current_state = @sku.current_marketing_state
    previous_state = @sku.marketing_states.create!(
      grade: "B",
      stage: "new",
      effective_at: current_state.effective_at - 1.day,
      ended_at: current_state.effective_at,
      changed_by: @developer
    )

    get "/ai/skus/overview",
      params: { sku: @sku.sku_code },
      headers: bearer_headers(@raw_api_token)

    assert_response :success
    assert_equal [
      {
        "marketing_grade" => "A",
        "marketing_stage" => "GRW",
        "effective_at" => current_state.effective_at.as_json,
        "ended_at" => nil
      },
      {
        "marketing_grade" => "B",
        "marketing_stage" => "NEW",
        "effective_at" => previous_state.effective_at.as_json,
        "ended_at" => previous_state.ended_at.as_json
      }
    ], response.parsed_body.dig("data", "marketing_state_history")
    assert_match "marketing_state_history", response.parsed_body.fetch("description")
  end

  test "returns sku general inventory" do
    received_batch = Ec::SkuBatch.create!(
      sku_code: @sku.sku_code,
      batch_code: "AI-RECEIVED-#{@token.upcase}",
      status: "received",
      batch_type: :normal,
      purchased_quantity: 20,
      received_quantity: 20,
      purchase_unit_price_cny: 1
    )
    incoming_batch = Ec::SkuBatch.create!(
      sku_code: @sku.sku_code,
      batch_code: "AI-INCOMING-#{@token.upcase}",
      status: "in_transit",
      batch_type: :normal,
      purchased_quantity: 12,
      received_quantity: 0,
      expected_arrival_on: Date.new(2026, 7, 30),
      memo: "On the way",
      purchase_unit_price_cny: 1
    )
    inventory_levels = [
      Ec::SkuInventoryLevel.create!(
        sku_code: @sku.sku_code,
        platform: "ozon",
        account_id: 10_001,
        store_name: "AI Ozon #{@token}",
        fulfillment_type: "fbo",
        quantity: 7,
        is_latest: true,
        synced_at: Time.current,
        metadata: {}
      ),
      Ec::SkuInventoryLevel.create!(
        sku_code: @sku.sku_code,
        platform: "ozon",
        account_id: 10_001,
        store_name: "AI Ozon #{@token}",
        fulfillment_type: "inbound",
        quantity: 2,
        is_latest: true,
        synced_at: Time.current,
        metadata: {}
      )
    ]

    get "/ai/skus/genernal_inventory",
      params: { sku: @sku.sku_code.downcase },
      headers: bearer_headers(@raw_api_token)

    assert_response :success
    assert_equal({
      "sku" => @sku.sku_code,
      "incoming_quantity" => 12,
      "book_stock" => 20,
      "platform_stock" => 7,
      "available_stock" => 11,
      "daily_sales_velocity" => "0.0",
      "turnover_days" => nil,
      "turnover_days_with_procurement" => nil,
      "incoming_batches" => [
        {
          "batch_code" => incoming_batch.batch_code,
          "status" => "in_transit",
          "expected_arrival_on" => "2026-07-30",
          "purchased_quantity" => 12,
          "memo" => "On the way"
        }
      ]
    }, response.parsed_body.fetch("data"))
    assert_match "FBS库存", response.parsed_body.fetch("description")
  ensure
    Ec::SkuInventoryLevel.where(id: inventory_levels&.map(&:id)).delete_all
    Ec::SkuBatch.where(id: [received_batch&.id, incoming_batch&.id].compact).delete_all
  end

  test "general inventory returns not found for unknown sku" do
    get "/ai/skus/genernal_inventory",
      params: { sku: "MISSING-#{@token}" },
      headers: bearer_headers(@raw_api_token)

    assert_response :not_found
    assert_equal({ "error" => "SKU not found" }, response.parsed_body)
  end

  test "general inventory requires sku parameter" do
    get "/ai/skus/genernal_inventory", headers: bearer_headers(@raw_api_token)

    assert_response :bad_request
    assert_equal({ "error" => "sku is required" }, response.parsed_body)
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
