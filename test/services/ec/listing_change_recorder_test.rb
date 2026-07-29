require "test_helper"
require "securerandom"

module Ec
  class ListingChangeRecorderTest < ActiveSupport::TestCase
    setup do
      @token = SecureRandom.hex(6)
      @admin = create_user("admin")
      @admin.roles << Role.find_by!(code: "super_admin")
      @operator = create_user("operator")
      @sku = Ec::Sku.create!(sku_code: "ACTION-#{@token}", product_name: "Action test")
      @store = Ec::Store.create!(
        platform: "wb",
        store_name: "Action store #{@token}",
        company_type: "small",
        is_active: true
      )
      @sku_product = Ec::SkuProduct.create!(
        sku: @sku,
        store: @store,
        product_id: "100#{@token.hex}",
        offer_id: @sku.sku_code
      )
    end

    teardown do
      Ec::OperationAction.where(ec_sku_product_id: @sku_product&.id).delete_all
      Ec::SkuProductOperator.where(sku_product_id: @sku_product&.id).delete_all
      Ec::SkuProduct.where(id: @sku_product&.id).delete_all
      Ec::Store.where(id: @store&.id).delete_all
      Ec::Sku.where(id: @sku&.id).delete_all
      UserRole.where(user_id: [@admin&.id, @operator&.id].compact).delete_all
      User.where(id: [@admin&.id, @operator&.id].compact).delete_all
    end

    test "records field and image diffs for the first assigned operator" do
      Ec::SkuProductOperator.create!(sku_product: @sku_product, user: @operator)

      action = Ec::ListingChangeRecorder.record(
        sku_product: @sku_product,
        operation_type: "listing_content",
        before: { title: "Old", images: %w[old-primary shared] },
        after: { title: "New", images: %w[new-primary shared] }
      )

      assert_equal @operator, action.operated_by_user
      assert_equal "assigned_operator", action.diff_result["attribution"]
      assert_equal({ "from" => "Old", "to" => "New" }, action.diff_result.dig("fields", "title"))
      assert_equal ["new-primary"], action.diff_result.dig("fields", "images", "added")
      assert_equal ["old-primary"], action.diff_result.dig("fields", "images", "removed")
    end

    test "falls back to the first active super admin" do
      action = Ec::ListingChangeRecorder.record(
        sku_product: @sku_product,
        operation_type: "listing_pricing",
        before: { price: BigDecimal("100.00") },
        after: { price: BigDecimal("90.00") }
      )

      assert_equal @admin, action.operated_by_user
      assert_equal "admin_fallback", action.diff_result["attribution"]
      assert_equal "100.0", action.diff_result.dig("fields", "price", "from")
      assert_equal "90.0", action.diff_result.dig("fields", "price", "to")
    end

    test "does not create an action when normalized values are unchanged" do
      assert_no_difference "Ec::OperationAction.count" do
        result = Ec::ListingChangeRecorder.record(
          sku_product: @sku_product,
          operation_type: "listing_specification",
          before: { price: BigDecimal("100.0"), attributes: { 1 => { value: "same" } } },
          after: { "price" => 100.0, "attributes" => { "1" => { "value" => "same" } } }
        )
        assert_nil result
      end
    end

    test "stores only changed nested specification values" do
      action = Ec::ListingChangeRecorder.record(
        sku_product: @sku_product,
        operation_type: "listing_specification",
        before: { attributes: { "10" => { name: "Color", values: ["red"] }, "20" => { name: "Width", values: [10] } } },
        after: { attributes: { "10" => { name: "Color", values: ["blue"] }, "20" => { name: "Width", values: [10] } } }
      )

      attributes_diff = action.diff_result.dig("fields", "attributes")
      assert_equal ["10"], attributes_diff.keys
      assert_equal({ "added" => ["blue"], "removed" => ["red"] }, attributes_diff.dig("10", "values"))
    end

    private

    def create_user(prefix)
      User.create!(
        email: "#{prefix}-listing-action-#{@token}@example.com",
        password: "password123",
        password_confirmation: "password123"
      )
    end
  end
end
