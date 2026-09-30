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
      Ec::SkuOperationPlan.where(sku_id: @sku&.id).delete_all
      Ec::SkuProductOperator.where(sku_product_id: @sku_product&.id).delete_all
      Ec::SkuOperatorAssignment.where(sku_code: @sku&.sku_code).delete_all
      Ec::SkuProduct.where(id: @sku_product&.id).delete_all
      Ec::Store.where(id: @store&.id).delete_all
      Ec::Sku.where(id: @sku&.id).delete_all
      UserRole.where(user_id: [@admin&.id, @operator&.id].compact).delete_all
      User.where(id: [@admin&.id, @operator&.id].compact).delete_all
    end

    test "records field and image diffs for the sku operator" do
      Ec::SkuOperatorAssignment.create!(sku: @sku, user: @operator)

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
          before: { price: BigDecimal("100.0"), volume_weight: BigDecimal("1.0"), attributes: { 1 => { value: "same" } } },
          after: { "price" => 100.0, "volume_weight" => 1, "attributes" => { "1" => { "value" => "same" } } }
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

    test "records advertisement identity with an advertising status change" do
      action = Ec::AdStatusChangeRecorder.record(
        sku_product: @sku_product,
        advertisement_id: "ADV-123",
        advertisement_name: "Summer campaign",
        before_status: 9,
        after_status: 11
      )

      assert_equal "sku_adv_on_off", action.operation_type
      assert_equal false, action.diff_result.dig("fields", "advertising_enabled", "to")
      assert_equal "ADV-123", action.diff_result.dig("advertisement", "id")
      assert_equal "Summer campaign", action.diff_result.dig("advertisement", "name")
      assert_equal "9.0", action.diff_result.dig("advertisement", "status_from")
      assert_equal "11.0", action.diff_result.dig("advertisement", "status_to")
    end

    test "does not record changes between two disabled advertising statuses" do
      assert_no_difference "Ec::OperationAction.count" do
        assert_nil Ec::AdStatusChangeRecorder.record(
          sku_product: @sku_product,
          advertisement_id: "ADV-123",
          advertisement_name: "Summer campaign",
          before_status: 11,
          after_status: 7
        )
      end
    end

    test "links a matching latest price plan and completes it at the operation time" do
      plan = create_plan(target: "price", operation: "increase")
      unrelated = create_plan(target: "advertising", operation: "open")
      old_plan = create_plan(target: "price", operation: "increase", is_latest: false)
      operated_at = Time.current

      action = Ec::ListingChangeRecorder.record(
        sku_product: @sku_product, operation_type: "listing_pricing",
        before: { price: 100 }, after: { price: 120 }, operated_at: operated_at
      )

      assert_equal plan, action.reload.plan
      assert plan.reload.done?
      assert_equal operated_at, plan.completed_at
      assert unrelated.reload.active?
      assert old_plan.reload.active?
    end

    test "does not complete plans for unrelated, opposite, historical, or unchanged operations" do
      plan = create_plan(target: "price", operation: "increase")
      unchanged = create_plan(target: "price", operation: "maintain")
      earlier = plan.created_at - 1.minute

      assert_nil Ec::ListingChangeRecorder.record(
        sku_product: @sku_product, operation_type: "listing_pricing",
        before: { price: 100 }, after: { price: 100 }
      )
      historical = Ec::ListingChangeRecorder.record(
        sku_product: @sku_product, operation_type: "listing_pricing",
        before: { price: 100 }, after: { price: 120 }, operated_at: earlier
      )
      opposite = Ec::ListingChangeRecorder.record(
        sku_product: @sku_product, operation_type: "listing_pricing",
        before: { price: 120 }, after: { price: 100 }
      )

      assert_nil historical.plan
      assert_nil opposite.plan
      assert plan.reload.active?
      assert unchanged.reload.active?
    end

    test "matches advertising status and listing image plans without completing other targets" do
      open_plan = create_plan(target: "advertising", operation: "open")
      image_plan = create_plan(target: "listing_image", operation: "modify")
      attribute_plan = create_plan(target: "listing_attribute", operation: "modify")

      opened = Ec::AdStatusChangeRecorder.record(
        sku_product: @sku_product, advertisement_id: "ADV-1", advertisement_name: "Test",
        before_status: 11, after_status: 9
      )
      image = Ec::ListingChangeRecorder.record(
        sku_product: @sku_product, operation_type: "listing_content",
        before: { images: [ "old" ] }, after: { images: [ "new" ] }
      )

      assert_equal open_plan, opened.plan
      assert_equal image_plan, image.plan
      assert open_plan.reload.done?
      assert image_plan.reload.done?
      assert attribute_plan.reload.active?
    end

    test "matches Ozon image fields without treating them as listing attributes" do
      %i[primary_image images360 color_image].each do |field|
        image_plan = create_plan(target: "listing_image", operation: "modify")
        attribute_plan = create_plan(target: "listing_attribute", operation: "modify")
        before = field == :images360 ? [ "old.jpg" ] : "old.jpg"
        after = field == :images360 ? [ "new.jpg" ] : "new.jpg"

        action = Ec::ListingChangeRecorder.record(
          sku_product: @sku_product, operation_type: "listing_content",
          before: { field => before }, after: { field => after }
        )

        assert_equal image_plan, action.plan
        assert attribute_plan.reload.active?
      end
    end

    test "does not complete a plan scoped to another listing" do
      other_product = Ec::SkuProduct.create!(
        sku: @sku, store: @store, product_id: "200#{@token.hex}", offer_id: "OTHER-#{@token}"
      )
      own_listing_plan = create_plan(target: "price", operation: "increase", scope: "LISTING", scope_id: @sku_product.id.to_s)
      other_listing_plan = create_plan(target: "price", operation: "increase", scope: "LISTING", scope_id: other_product.id.to_s)

      action = Ec::ListingChangeRecorder.record(
        sku_product: @sku_product, operation_type: "listing_pricing",
        before: { price: 100 }, after: { price: 120 }
      )

      assert_equal own_listing_plan, action.plan
      assert other_listing_plan.reload.active?
    ensure
      other_product&.destroy!
    end

    test "matches a SKU scoped plan for a listing action" do
      plan = create_plan(target: "listing_attribute", operation: "modify", scope: "SKU", scope_id: @sku.sku_code)

      action = Ec::ListingChangeRecorder.record(
        sku_product: @sku_product, operation_type: "listing_specification",
        before: { width: 10 }, after: { width: 12 }
      )

      assert_equal plan, action.plan
    end

    test "does not infer an advertising close from an unknown status" do
      plan = create_plan(target: "advertising", operation: "close")
      action = Ec::OperationAction.create!(
        operation_type: "sku_adv_on_off", operated_by_user: @admin, operated_at: Time.current,
        sku_product: @sku_product, sku: @sku, store: @store,
        diff_result: { "fields" => { "advertising_enabled" => { "from" => true, "to" => nil } } }
      )

      Ec::OperationActionPlanMatcher.call(action)

      assert_nil action.reload.plan
      assert plan.reload.active?
    end

    test "links only one matching plan per synced action" do
      older = create_plan(target: "listing_attribute", operation: "modify")
      newer = create_plan(target: "listing_attribute", operation: "modify")
      action = Ec::ListingChangeRecorder.record(
        sku_product: @sku_product, operation_type: "listing_specification",
        before: { dimensions: "old" }, after: { dimensions: "new" }
      )

      assert_equal newer, action.plan
      assert older.reload.active?
    end

    test "does not link an expired or cancelled plan" do
      expired = create_plan(
        target: "price", operation: "increase", plan_date: Date.current - 2.weeks,
        created_at: 2.weeks.ago, retain_until: 1.minute.ago
      )
      completed = create_plan(target: "price", operation: "increase", status: "ignored")
      action = Ec::ListingChangeRecorder.record(
        sku_product: @sku_product, operation_type: "listing_pricing",
        before: { price: 100 }, after: { price: 120 }
      )

      assert_nil action.plan
      assert expired.reload.active?
      assert completed.reload.ignored?
    end

    test "links a historical action even after the current retain window" do
      period_start = Date.new(2026, 9, 14)
      operated_at = Time.find_zone!(Ec::SkuOperationPlan::TIME_ZONE).local(2026, 9, 16, 12)
      plan = create_plan(
        target: "price", operation: "increase", plan_date: period_start,
        created_at: operated_at - 1.day,
        retain_until: operated_at - 1.minute
      )

      action = Ec::ListingChangeRecorder.record(
        sku_product: @sku_product, operation_type: "listing_pricing",
        before: { price: 100 }, after: { price: 120 }, operated_at: operated_at
      )

      assert_equal plan, action.plan
    end

    test "matches inbound inventory changes to warehouse distribution plans" do
      plan = create_plan(target: "warehouse_distribution", operation: "increase")

      action = Ec::ListingChangeRecorder.record(
        sku_product: @sku_product, operation_type: "sku_inbound_change",
        before: { platform_inbound_quantity: 2 }, after: { platform_inbound_quantity: 8 }
      )

      assert_equal plan, action.plan
    end

    test "matches price and advertising budget decreases" do
      [["price", "listing_pricing", "price"], ["advertising", "sku_adv_budget", "daily_budget"]].each do |target, type, field|
        plan = create_plan(target: target, operation: "decrease")
        action = Ec::ListingChangeRecorder.record(sku_product: @sku_product, operation_type: type,
          before: { field => 100 }, after: { field => 80 })
        assert_equal plan, action.plan
      end
    end

    test "matches all supported shipment statuses to warehouse distribution" do
      plan = create_plan(target: "warehouse_distribution", operation: "modify")
      %w[planned unloading_allowed accepting accepted unloaded_at_gate READY_TO_SUPPLY
        ACCEPTED_AT_SUPPLY_WAREHOUSE IN_TRANSIT ACCEPTANCE_AT_STORAGE_WAREHOUSE COMPLETED].each do |status|
        action = Ec::OperationAction.create!(sku: @sku, sku_product: @sku_product, store: @store,
          operated_by_user: @admin, operation_type: "supply_order", operated_at: Time.current,
          diff_result: { fields: { supply_order_status: { from: "new", to: status } }, supply_order: { sku_quantity: 10 } })
        Ec::OperationActionPlanMatcher.call(action)
        assert_equal plan, action.reload.plan, status
      end
      assert_equal 10, plan.operation_actions.count
    end

    test "leaves cancellation inbound decreases manual notes and maintain plans unmatched" do
      create_plan(target: "warehouse_distribution", operation: "increase")
      create_plan(target: "price", operation: "maintain")
      [
        ["supply_order", { fields: { supply_order_status: { from: "READY_TO_SUPPLY", to: "CANCELLED" } }, supply_order: { sku_quantity: 10 } }],
        ["sku_inbound_change", { fields: { quantity: { from: 10, to: 0 } } }],
        ["manual_note", { note: "Discussion only" }],
        ["listing_pricing", { fields: { price: { from: 100, to: 100 } } }]
      ].each do |type, diff|
        action = Ec::OperationAction.create!(sku: @sku, sku_product: @sku_product, store: @store,
          operated_by_user: @admin, operation_type: type, operated_at: Time.current, diff_result: diff)
        Ec::OperationActionPlanMatcher.call(action)
        assert_nil action.reload.plan_id, type
      end
    end

    test "matches a non-latest historical plan until the Shanghai deadline inclusive" do
      zone = Time.find_zone!(Ec::SkuOperationPlan::TIME_ZONE)
      period_start = Date.new(2026, 9, 21)
      plan = create_plan(target: "price", operation: "increase", plan_date: period_start,
        created_at: zone.local(2026, 9, 22), is_latest: false)
      before = Ec::ListingChangeRecorder.record(sku_product: @sku_product, operation_type: "listing_pricing",
        before: { price: 100 }, after: { price: 120 }, operated_at: zone.local(2026, 9, 21, 12))
      assert_nil before.plan
      within = Ec::ListingChangeRecorder.record(sku_product: @sku_product, operation_type: "listing_pricing",
        before: { price: 100 }, after: { price: 120 }, operated_at: zone.local(2026, 9, 28, 23, 59, 59))
      assert_equal plan, within.plan
      late = Ec::ListingChangeRecorder.record(sku_product: @sku_product, operation_type: "listing_pricing",
        before: { price: 120 }, after: { price: 130 }, operated_at: zone.local(2026, 9, 29))
      assert_nil late.plan
      replacement = create_plan(target: "price", operation: "increase", plan_date: period_start,
        created_at: zone.local(2026, 9, 22), is_latest: true)
      Ec::OperationActionPlanMatcher.call(within)
      assert_equal plan, within.reload.plan
      assert_equal "not_started", replacement.reload.execution_status
    end

    test "removing a regenerated plan leaves its operation action intact" do
      plan = create_plan(target: "price", operation: "increase")
      action = Ec::ListingChangeRecorder.record(
        sku_product: @sku_product, operation_type: "listing_pricing",
        before: { price: 100 }, after: { price: 120 }
      )

      plan.delete

      assert_nil action.reload.plan_id
      assert Ec::OperationAction.exists?(action.id)
    end

    private

    def create_plan(target:, operation:, **attributes)
      @sku.sku_operation_plans.create!(target: target, operation: operation,
        referer: [ "listing_change_#{@token}" ], message: "Change listing #{@token}", **attributes)
    end

    def create_user(prefix)
      User.create!(
        email: "#{prefix}-listing-action-#{@token}@example.com",
        password: "password123",
        password_confirmation: "password123"
      )
    end
  end
end
