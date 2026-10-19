require "test_helper"
require "securerandom"

module Ec
  class FunnelAnomalyNotifierTest < ActiveSupport::TestCase
    setup do
      @token = SecureRandom.hex(6)
      @admin = User.create!(email: "funnel-notification-admin-#{@token}@example.com", password: "password123")
      @admin.roles << Role.find_by!(code: "super_admin")
      @operator = User.create!(email: "funnel-notification-operator-#{@token}@example.com", password: "password123")
      @sku = Ec::Sku.create!(sku_code: "FUNNEL-#{@token}", product_name: "Funnel SKU")
      @store = Ec::Store.create!(platform: "ozon", store_name: "Funnel store #{@token}", company_type: "small", is_active: true)
      Ec::SkuOperatorAssignment.create!(sku: @sku, user: @operator)
    end

    teardown do
      Ec::SystemNotificationRecipient.where(user_id: [@admin&.id, @operator&.id]).delete_all
      notification_ids = Ec::SystemNotification.where(store_id: @store&.id).select(:id)
      Ec::SystemNotificationRecipient.where(notification_id: notification_ids).delete_all
      Ec::SystemNotification.where(id: notification_ids).delete_all
      Ec::SkuOperatorAssignment.where(sku_code: @sku&.sku_code).delete_all
      Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
      Ec::Store.where(id: @store&.id).delete_all
      UserRole.where(user_id: [@admin&.id, @operator&.id]).delete_all
      User.where(id: [@admin&.id, @operator&.id]).delete_all
    end

    test "notifies when orders collapse against the recent baseline" do
      Ec::FunnelAnomalyNotifier.call(
        observations: [{
          sku_code: @sku.sku_code,
          current: { "views" => 100, "orders" => 2 },
          baseline: { "views" => 110, "orders" => 10 }
        }],
        store: @store,
        as_of: Date.new(2026, 10, 18)
      )

      notification = Ec::SystemNotification.where(sku_code: @sku.sku_code).sole
      assert_equal "funnel_anomaly", notification.notification_type
      assert_includes notification.target_path, "tab=sales_funnel"
      assert_includes notification.recipients.pluck(:user_id), @admin.id
      assert_includes notification.recipients.pluck(:user_id), @operator.id
    end
  end
end
