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
    content_action = create_action(
      operation_type: "listing_content",
      operated_at: @time_zone.parse("2026-08-04 12:00"),
      diff_result: {
        "fields" => {
          "title" => { "from" => "Old", "to" => "New" },
          "description" => { "from" => "Old description", "to" => nil },
          "images" => { "added" => [ "new.jpg" ], "removed" => [ "old.jpg" ] }
        }
      }
    )
    specification_action = create_action(
      operation_type: "listing_specification",
      operated_at: @time_zone.parse("2026-08-04 13:00"),
      diff_result: {
        "fields" => {
          "attributes" => {
            "10" => { "values" => { "added" => [ "blue" ], "removed" => [ "red" ] } },
            "20" => { "from" => { "name" => "Width" }, "to" => nil },
            "30" => { "from" => nil, "to" => { "name" => "Height" } }
          },
          "dimensions" => {
            "width" => { "from" => 10, "to" => 12 },
            "height" => { "from" => 20, "to" => nil }
          }
        }
      }
    )

    result = I18n.with_locale(:zh) do
      ErpAI::V3::OperationActionsFullPeriodContext.new(
        sku: @sku, period_from: Date.new(2026, 8, 3), period_to: Date.new(2026, 8, 9), time_zone: @time_zone
      ).call
    end

    assert_equal 3, result.size
    row = result.find { |item| item.fetch(:action_id) == pricing_action.id }
    assert_equal pricing_action.id, row.fetch(:action_id)
    assert_equal "listing_pricing", row.fetch(:operation_type)
    assert row.fetch(:operation_type_label).present?
    assert_equal({ "from" => 100, "to" => 120 }, row.dig(:diff_result, "fields", "marketing_price"))
    assert row.fetch(:diff_summary).any? { |summary| summary.include?("100") && summary.include?("120") }

    content_row = result.find { |item| item.fetch(:action_id) == content_action.id }
    assert_equal [ "修改了2个属性，删除了1个属性" ], content_row.fetch(:diff_summary)
    assert_equal "New", content_row.dig(:diff_result, "fields", "title", "to")

    specification_row = result.find { |item| item.fetch(:action_id) == specification_action.id }
    assert_equal [ "修改了3个属性，删除了2个属性" ], specification_row.fetch(:diff_summary)
    assert_equal "blue", specification_row.dig(:diff_result, "fields", "attributes", "10", "values", "added", 0)
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
