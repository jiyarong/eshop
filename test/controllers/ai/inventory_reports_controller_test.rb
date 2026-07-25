require "test_helper"

class ErpAI::InventoryReportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(4)
    @user = create_user_with_roles("ai-inventory-#{@token}@example.com", "manager")
    @raw_api_token, = UserApiKey.generate_for!(@user, name: "Inventory Agent")
    @sku = Ec::Sku.create!(
      sku_code: "AI-INV-#{@token.upcase}",
      product_name: "AI inventory #{@token}"
    )
  end

  teardown do
    Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
    UserApiKey.where(user: @user).delete_all
    UserRole.where(user: @user).delete_all
    User.where(id: @user.id).delete_all
  end

  test "requires an api key with report permission" do
    post "/ai/inventory_reports.json", params: { sku: @sku.sku_code }

    assert_response :unauthorized
  end

  test "returns filtered list and detail data together with pagination" do
    post "/ai/inventory_reports.json",
      params: {
        sku: @sku.sku_code.downcase,
        page: 1,
        detail_tab: "book",
        book_batch_page: 1
      },
      headers: bearer_headers(@raw_api_token)

    assert_response :success
    body = response.parsed_body
    assert_equal true, body.fetch("success")
    assert_equal "ok", body.fetch("message")
    assert_equal 1, body.dig("data", "pagination", "page")
    assert_equal 10, body.dig("data", "pagination", "page_size")
    assert_equal 1, body.dig("data", "pagination", "total_count")

    row = body.dig("data", "rows").sole
    assert_equal @sku.sku_code, row.dig("list", "sku_code")
    assert_equal @sku.sku_code, row.dig("detail", "sku_code")
    assert_equal "book", row.dig("detail", "active_detail_tab")
    assert_equal 1, row.dig("detail", "book_batch_pagination", "page")
    assert body.dig("data", "volume_summary").key?("pending_stock_volume_m3")
  end

  private

  def bearer_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end
end
