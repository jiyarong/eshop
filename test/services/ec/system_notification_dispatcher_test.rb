require "test_helper"
require "securerandom"

module Ec
  class SystemNotificationDispatcherTest < ActiveSupport::TestCase
    setup do
      @token = SecureRandom.hex(6)
      @admin = User.create!(email: "notification-admin-#{@token}@example.com", password: "password123")
      @admin.roles << Role.find_by!(code: "super_admin")
      @developer = User.create!(email: "notification-developer-#{@token}@example.com", password: "password123")
      @sku = Ec::Sku.create!(sku_code: "NOTIFY-#{@token}", product_name: "Notification SKU")
      @store = Ec::Store.create!(platform: "ozon", store_name: "Notification store #{@token}", company_type: "small", is_active: true)
      Ec::SkuDeveloperAssignment.create!(sku: @sku, user: @developer)
    end

    teardown do
      Ec::SystemNotificationRecipient.where(user_id: [@admin&.id, @developer&.id]).delete_all
      notification_ids = Ec::SystemNotification.where(store_id: @store&.id).select(:id)
      Ec::SystemNotificationRecipient.where(notification_id: notification_ids).delete_all
      Ec::SystemNotification.where(id: notification_ids).delete_all
      Ec::SkuDeveloperAssignment.where(sku_code: @sku&.sku_code).delete_all
      Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
      Ec::Store.where(id: @store&.id).delete_all
      UserRole.where(user_id: [@admin&.id, @developer&.id]).delete_all
      User.where(id: [@admin&.id, @developer&.id]).delete_all
    end

    test "delivers to assigned developer and admin and deduplicates active fingerprint" do
      attributes = {
        notification_type: "price_anomaly",
        severity: "warning",
        title: "Price changed",
        body: "Check this SKU",
        target_path: "/reports/skus/#{@sku.sku_code}",
        occurred_at: Time.current,
        sku_code: @sku.sku_code,
        store: @store,
        metadata: { "after" => 120 },
        fingerprint: "notification-test-#{@token}"
      }

      notification = Ec::SystemNotificationDispatcher.call(**attributes)
      Ec::SystemNotificationDispatcher.call(**attributes.merge(severity: "critical", occurred_at: 1.minute.from_now))

      assert_equal 1, Ec::SystemNotification.where(fingerprint: attributes[:fingerprint]).count
      assert_equal 2, notification.reload.occurrence_count
      assert_equal "critical", notification.severity
      assert_includes notification.recipients.pluck(:user_id), @admin.id
      assert_includes notification.recipients.pluck(:user_id), @developer.id
    end

    test "recipient state is independent and soft deletion keeps the event" do
      notification = Ec::SystemNotificationDispatcher.call(
        notification_type: "funnel_anomaly", severity: "warning", title: "Funnel", body: "Check",
        target_path: "/reports/sales_funnel", occurred_at: Time.current, sku_code: @sku.sku_code,
        store: @store, fingerprint: "notification-state-#{@token}"
      )
      recipient = notification.recipients.find_by!(user: @developer)

      recipient.read!
      assert_not recipient.unread?
      recipient.unread!
      assert recipient.unread?
      recipient.delete!
      assert_not recipient.reload.deleted_at.nil?
      assert notification.reload.active?
    end
  end
end
