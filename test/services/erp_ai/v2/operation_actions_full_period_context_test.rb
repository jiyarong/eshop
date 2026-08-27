require "test_helper"

class ErpAI::V2::OperationActionsFullPeriodContextTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(4).upcase
    @time_zone = ActiveSupport::TimeZone["Asia/Shanghai"]
    @user = User.create!(
      email: "operation-context-#{@token.downcase}@example.com",
      password: "password123",
      name: "Operation context user #{@token}"
    )
    @sku = Ec::Sku.create!(sku_code: "OPERATION-CONTEXT-#{@token}", product_name: "Operation context")
    @store = Ec::Store.create!(platform: "ozon", store_name: "Operation context #{@token}", company_type: "small")
    @product = Ec::SkuProduct.create!(
      sku: @sku, store: @store, product_id: "PRODUCT-#{@token}", platform_sku_id: "81001", offer_id: "OFFER-#{@token}"
    )
  end

  teardown do
    Ec::OperationAction.where(ec_sku_id: @sku&.id).delete_all
    Ec::SkuProduct.where(id: @product&.id).delete_all
    Ec::Store.where(id: @store&.id).delete_all
    Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
    User.where(id: @user&.id).delete_all
  end

  test "keeps before and after values while removing nested raw payloads" do
    action = create_action(
      operated_at: @time_zone.parse("2026-08-04 10:00"),
      diff_result: {
        "before" => { "enabled" => false, "raw_json" => { "large" => true } },
        "after" => { "enabled" => true, "source_payload" => { "large" => true } },
        "fields" => { "daily_budget" => { "from" => 100, "to" => 200 } },
        "raw_payload" => { "large" => true }
      }
    )
    create_action(operated_at: @time_zone.parse("2026-07-31 10:00"), diff_result: { "note" => "outside" })

    result = ErpAI::V2::OperationActionsFullPeriodContext.new(
      sku: @sku, period_from: Date.new(2026, 8, 3), period_to: Date.new(2026, 8, 9), time_zone: @time_zone
    ).call

    row = result.sole
    assert_equal action.id, row.fetch(:action_id)
    assert_equal false, row.dig(:diff_result, "before", "enabled")
    assert_equal true, row.dig(:diff_result, "after", "enabled")
    assert_equal({ "from" => 100, "to" => 200 }, row.dig(:diff_result, "fields", "daily_budget"))
    assert_not row.fetch(:diff_result).key?("raw_payload")
    assert_not row.dig(:diff_result, "before").key?("raw_json")
    assert_not row.dig(:diff_result, "after").key?("source_payload")
  end

  private

  def create_action(operated_at:, diff_result:)
    Ec::OperationAction.create!(
      operation_type: "listing_pricing",
      operated_by_user: @user,
      operated_at: operated_at,
      sku_product: @product,
      sku: @sku,
      store: @store,
      diff_result: diff_result,
      record_by_system: true
    )
  end
end
