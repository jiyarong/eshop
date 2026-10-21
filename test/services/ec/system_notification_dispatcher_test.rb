require "test_helper"
require "securerandom"

module Ec
  class SystemNotificationDispatcherTest < ActiveSupport::TestCase
    self.use_transactional_tests = true

    setup do
      @token = SecureRandom.hex(6)
      @admin = User.create!(email: "notification-admin-#{@token}@example.com", password: "password123")
      @admin.roles << Role.find_by!(code: "super_admin")
      @developer = User.create!(email: "notification-developer-#{@token}@example.com", password: "password123")
      @sku = Ec::Sku.create!(sku_code: "NOTIFY-#{@token}", product_name: "Notification SKU")
      @store = Ec::Store.create!(platform: "ozon", store_name: "Notification store #{@token}", company_type: "small", is_active: true)
      Ec::SkuDeveloperAssignment.create!(sku: @sku, user: @developer)
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
      assert @admin.system_notification_recipients.inbox.sole.notification.digest_notifications.exists?(notification.id)
      assert @developer.system_notification_recipients.inbox.sole.notification.digest_notifications.exists?(notification.id)
    end

    test "recipient state is independent and soft deletion keeps the event" do
      notification = Ec::SystemNotificationDispatcher.call(
        notification_type: "funnel_anomaly", severity: "warning", title: "Funnel", body: "Check",
        target_path: "/reports/sales_funnel", occurred_at: Time.current, sku_code: @sku.sku_code,
        store: @store, fingerprint: "notification-state-#{@token}"
      )
      recipient = @developer.system_notification_recipients.inbox.sole

      recipient.read!
      assert_not recipient.unread?
      recipient.unread!
      assert recipient.unread?
      recipient.delete!
      assert_not recipient.reload.deleted_at.nil?
      assert notification.reload.active?
    end

    test "delivers one daily summary with only the user's assigned events across types and stores" do
      attributes = { notification_type: "funnel_anomaly", severity: "warning", title: "Funnel", body: "Metrics",
        target_path: "/reports/sales_funnel", store: @store, sku_code: @sku.sku_code }
      first = Ec::SystemNotificationDispatcher.call(**attributes, fingerprint: "first-#{@token}")
      second = Ec::SystemNotificationDispatcher.call(**attributes.merge(notification_type: "price_anomaly", store: nil),
        fingerprint: "second-#{@token}")
      admin_only = Ec::SystemNotificationDispatcher.call(**attributes.merge(sku_code: nil), fingerprint: "admin-#{@token}")
      Ec::SystemNotificationDispatcher.call(**attributes, fingerprint: "first-#{@token}")

      developer = @developer.system_notification_recipients.inbox.sole
      admin = @admin.system_notification_recipients.inbox.sole
      assert_equal [ first.id, second.id ].sort, developer.notification.digest_notifications.ids.sort
      assert_equal [ first.id, second.id, admin_only.id ].sort, admin.notification.digest_notifications.ids.sort
      assert_equal 2, developer.notification.occurrence_count
      assert_equal 3, admin.notification.occurrence_count
      assert_equal 1, @developer.system_notification_recipients.count
      assert_equal 1, @admin.system_notification_recipients.count
    end
  end
end
