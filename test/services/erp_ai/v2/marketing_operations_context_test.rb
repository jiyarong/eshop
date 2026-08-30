require "test_helper"

class ErpAI::V2::MarketingOperationsContextTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(4).upcase
    @time_zone = ActiveSupport::TimeZone["Asia/Shanghai"]
    @user = User.create!(email: "marketing-operations-#{@token.downcase}@example.com", password: "password123", name: "Marketing operations #{@token}")
    @sku = Ec::Sku.create!(sku_code: "MARKETING-OPERATIONS-#{@token}", product_name: "Marketing operations")
    @store = Ec::Store.create!(platform: "ozon", store_name: "Marketing operations #{@token}", company_type: "small")
    @product = Ec::SkuProduct.create!(sku: @sku, store: @store, product_id: "PRODUCT-#{@token}", platform_sku_id: @token.to_i(16).to_s, offer_id: "OFFER-#{@token}")
  end

  teardown do
    Ec::OperationAction.where(ec_sku_id: @sku&.id).delete_all
    Ec::SkuProduct.where(id: @product&.id).delete_all
    Ec::Store.where(id: @store&.id).delete_all
    Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
    User.where(id: @user&.id).delete_all
  end

  test "summarizes operations and compacts the most recent twenty actions" do
    21.times do |index|
      create_action(
        operated_at: @time_zone.parse("2026-08-#{format('%02d', index + 1)} 10:00"),
        record_by_system: index.even?,
        diff_result: index == 20 ? verbose_diff : { "fields" => { "price" => { "from" => index, "to" => index + 1 } } }
      )
    end

    result = described_context.call

    assert_equal 21, result.dig(:summary, :total_count)
    assert_equal 11, result.dig(:summary, :system_recorded_count)
    assert_equal 10, result.dig(:summary, :user_recorded_count)
    assert_equal({ "listing_pricing" => 21 }, result.dig(:summary, :by_type))
    assert_equal 20, result.dig(:summary, :recent_limit)
    assert_equal true, result.dig(:summary, :recent_truncated)
    assert_equal 20, result.fetch(:recent).size
    assert_equal "2026-08-02", result.fetch(:recent).first.fetch(:operated_at).to_date.iso8601

    latest = result.fetch(:recent).last
    assert_equal @product.id, latest.fetch(:sku_product_id)
    assert_equal @product.product_id, latest.fetch(:platform_product_id)
    assert_equal @product.platform_sku_id, latest.fetch(:platform_sku_id)
    assert_equal @product.offer_id, latest.fetch(:offer_id)
    assert_equal 500 + 3, latest.fetch(:notes).sole.length
    assert_equal({ "changed" => true, "length" => 241 }, latest.dig(:changes, "long_value"))
    assert_equal 6, latest.dig(:changes, "items", "count")
    assert_equal 5, latest.dig(:changes, "items", "sample").size
    assert_equal 1, latest.dig(:changes, "omitted_key_count")
  end

  test "reads note changes from JSON-style string keys" do
    create_action(
      operated_at: @time_zone.parse("2026-08-15 10:00"),
      record_by_system: false,
      diff_result: { "fields" => { "note" => { "from" => "old", "to" => "new" } } }
    )

    notes = described_context.call.fetch(:recent).sole.fetch(:notes)
    assert_equal [ "new" ], notes
  end

  test "accepts a note field stored directly as a string" do
    create_action(
      operated_at: @time_zone.parse("2026-08-16 10:00"),
      record_by_system: false,
      diff_result: { "fields" => { "note" => "direct note" } }
    )

    action = described_context.call.fetch(:recent).sole
    assert_equal [ "direct note" ], action.fetch(:notes)
  end

  test "ignores malformed non-object diff payloads" do
    create_action(
      operated_at: @time_zone.parse("2026-08-17 10:00"),
      record_by_system: false,
      diff_result: { "fields" => "malformed" }
    )

    action = described_context.call.fetch(:recent).sole
    assert_equal({}, action.fetch(:changes))
    assert_equal [], action.fetch(:notes)
  end

  test "uses the WB nmId as the platform SKU identifier" do
    account = RawWb::SellerAccount.create!(
      name: "Marketing operations WB #{@token}", api_token: "operations-wb-#{@token}", company_type: :small
    )
    store = Ec::Store.create!(
      platform: "wb", store_name: "Marketing operations WB #{@token}", company_type: "small",
      wb_raw_account_id: account.id
    )
    product = Ec::SkuProduct.create!(sku: @sku, store: store, product_id: "71001", offer_id: "WB-OFFER-#{@token}")
    action = Ec::OperationAction.create!(
      operation_type: "listing_content", operated_by_user: @user,
      operated_at: @time_zone.parse("2026-08-18 10:00"), sku_product: product, sku: @sku, store: store,
      diff_result: { "fields" => { "title" => { "from" => "old", "to" => "new" } } },
      record_by_system: true
    )

    payload = described_context.call.fetch(:recent).find { |row| row.fetch(:action_id) == action.id }
    assert_equal "71001", payload.fetch(:platform_sku_id)
  ensure
    Ec::OperationAction.where(id: action&.id).delete_all
    Ec::SkuProduct.where(id: product&.id).delete_all
    Ec::Store.where(id: store&.id).delete_all
    RawWb::SellerAccount.where(id: account&.id).delete_all
  end

  private

  def described_context
    ErpAI::V2::MarketingOperationsContext.new(
      sku: @sku, period_from: Date.new(2026, 8, 1), period_to: Date.new(2026, 8, 31), time_zone: @time_zone
    )
  end

  def create_action(operated_at:, record_by_system:, diff_result:)
    Ec::OperationAction.create!(
      operation_type: "listing_pricing", operated_by_user: @user, operated_at: operated_at,
      sku_product: @product, sku: @sku, store: @store, diff_result: diff_result,
      record_by_system: record_by_system
    )
  end

  def verbose_diff
    fields = {
      "long_value" => "x" * 241,
      "items" => (1..6).to_a,
      "note" => { "to" => "n" * 501 }
    }
    fields.merge!((1..18).to_h { |index| [ "field_#{index}", index ] })
    { "fields" => fields }
  end
end
