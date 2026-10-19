require "test_helper"
require "securerandom"

module Ec
  class PriceAnomalyNotifierTest < ActiveSupport::TestCase
    setup do
      @token = SecureRandom.hex(6)
      @admin = User.create!(email: "price-notification-admin-#{@token}@example.com", password: "password123")
      @admin.roles << Role.find_by!(code: "super_admin")
      @operator = User.create!(email: "price-notification-operator-#{@token}@example.com", password: "password123")
      @sku = Ec::Sku.create!(sku_code: "PRICE-#{@token}", product_name: "Price SKU")
      @store = Ec::Store.create!(platform: "ozon", store_name: "Price store #{@token}", company_type: "small", is_active: true)
      @product = Ec::SkuProduct.create!(sku: @sku, store: @store, product_id: "P-#{@token}", offer_id: @sku.sku_code)
      Ec::SkuOperatorAssignment.create!(sku: @sku, user: @operator)
      @action = Ec::OperationAction.create!(
        operation_type: "listing_pricing", operated_by_user: @operator, operated_at: Time.current,
        sku_product: @product, sku: @sku, store: @store,
        diff_result: { "fields" => { "marketing_price" => { "from" => "5000", "to" => "10000" } } },
        record_by_system: true
      )
    end

    teardown do
      Ec::SystemNotificationRecipient.where(user_id: [@admin&.id, @operator&.id]).delete_all
      notification_ids = Ec::SystemNotification.where(store_id: @store&.id).select(:id)
      Ec::SystemNotificationRecipient.where(notification_id: notification_ids).delete_all
      Ec::SystemNotification.where(id: notification_ids).delete_all
      Ec::OperationAction.where(id: @action&.id).delete_all
      Ec::SkuOperatorAssignment.where(sku_code: @sku&.sku_code).delete_all
      Ec::SkuProduct.where(id: @product&.id).delete_all
      Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
      Ec::Store.where(id: @store&.id).delete_all
      UserRole.where(user_id: [@admin&.id, @operator&.id]).delete_all
      User.where(id: [@admin&.id, @operator&.id]).delete_all
    end

    test "notifies assigned operator and admin for a large price increase" do
      Ec::PriceAnomalyNotifier.call(actions: [@action], store: @store)

      notification = Ec::SystemNotification.where(sku_code: @sku.sku_code).sole
      assert_equal "price_anomaly", notification.notification_type
      assert_equal "critical", notification.severity
      assert_includes notification.body, "10000"
      assert_includes notification.recipients.pluck(:user_id), @admin.id
      assert_includes notification.recipients.pluck(:user_id), @operator.id
      assert_equal "/reports/skus/#{@sku.sku_code}?tab=operation_actions", notification.target_path
    end

    test "ignores small price changes" do
      @action.update!(diff_result: { "fields" => { "marketing_price" => { "from" => "5000", "to" => "5400" } } })

      Ec::PriceAnomalyNotifier.call(actions: [@action], store: @store)

      assert_empty Ec::SystemNotification.where(sku_code: @sku.sku_code)
    end
  end
end
