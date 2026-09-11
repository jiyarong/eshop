require "test_helper"

class ErpAI::V3::OperationActionsFullPeriodContextTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(4).upcase
    @time_zone = ActiveSupport::TimeZone["Asia/Shanghai"]
    @user = User.create!(
      email: "operation-v3-context-#{@token.downcase}@example.com",
      password: "password123",
      name: "Operation v3 context user #{@token}"
    )
    @sku = Ec::Sku.create!(sku_code: "OPERATION-V3-CONTEXT-#{@token}", product_name: "Operation v3 context")
    @store = Ec::Store.create!(platform: "ozon", store_name: "Operation v3 context #{@token}", company_type: "small")
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

  test "adds human readable summaries while preserving full diffs" do
    pricing_action = create_action(
      operation_type: "listing_pricing",
      operated_at: @time_zone.parse("2026-08-04 10:00"),
      diff_result: {
        "fields" => {
          "marketing_price" => { "from" => 100, "to" => 120 }
        }
      }
    )
    create_action(
      operation_type: "sku_inbound_change",
      operated_at: @time_zone.parse("2026-08-04 11:00"),
      diff_result: {
        "fields" => {
          "platform_inbound_quantity" => { "from" => 0, "to" => 10 }
        }
      }
    )

    result = ErpAI::V3::OperationActionsFullPeriodContext.new(
      sku: @sku, period_from: Date.new(2026, 8, 3), period_to: Date.new(2026, 8, 9), time_zone: @time_zone
    ).call

    row = result.sole
    assert_equal pricing_action.id, row.fetch(:action_id)
    assert_equal "listing_pricing", row.fetch(:operation_type)
    assert row.fetch(:operation_type_label).present?
    assert_equal({ "from" => 100, "to" => 120 }, row.dig(:diff_result, "fields", "marketing_price"))
    assert row.fetch(:diff_summary).any? { |summary| summary.include?("100") && summary.include?("120") }
  end

  private

  def create_action(operation_type:, operated_at:, diff_result:)
    Ec::OperationAction.create!(
      operation_type: operation_type,
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
