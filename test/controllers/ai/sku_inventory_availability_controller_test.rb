require "test_helper"

class ErpAI::SkuInventoryAvailabilityControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(4)
    @user = create_user_with_roles("inventory-availability-#{@token}@example.com", "manager")
    @raw_api_token, = UserApiKey.generate_for!(@user, name: "Grade Inspector")
    @sku = Ec::Sku.create!(sku_code: "AVAILABILITY-#{@token.upcase}", product_name: "Availability", is_active: true)
    Ec::Snapshot.create!(
      snapshot_type: Ec::InventorySnapshot.snapshot_type,
      snapshot_date: Date.new(2026, 7, 20),
      sku: @sku,
      content: {
        overview: {
          platform_stock: 12,
          available_stock: 3,
          out_of_stock: false,
          platform_totals: { wb: { platform_stock: 12 } }
        }
      }
    )
  end

  teardown do
    Ec::Snapshot.where(sku_id: @sku&.id).delete_all
    Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
    UserApiKey.where(user_id: @user&.id).delete_all
    UserRole.where(user_id: @user&.id).delete_all
    User.where(id: @user&.id).delete_all
  end

  test "returns one raw inventory evidence row for every requested date" do
    get "/ai/skus/inventory_availability",
      params: { sku: @sku.sku_code, from_date: "2026-07-20", to_date: "2026-07-21" },
      headers: bearer_headers

    assert_response :success
    data = response.parsed_body.fetch("data")
    assert_equal @sku.sku_code, data.fetch("sku")
    assert_equal({ "from_date" => "2026-07-20", "to_date" => "2026-07-21" }, data.fetch("period"))
    assert_equal 2, data.fetch("days").size
    assert_equal true, data.dig("days", 0, "available")
    assert_equal 12, data.dig("days", 0, "platform_stock")
    assert_equal false, data.dig("days", 1, "available")
  end

  test "rejects a range longer than eight weeks" do
    get "/ai/skus/inventory_availability",
      params: { sku: @sku.sku_code, from_date: "2026-06-01", to_date: "2026-07-27" },
      headers: bearer_headers

    assert_response :bad_request
    assert_equal "invalid_date_range", response.parsed_body.fetch("error")
  end

  private

  def bearer_headers
    { "Authorization" => "Bearer #{@raw_api_token}" }
  end
end
