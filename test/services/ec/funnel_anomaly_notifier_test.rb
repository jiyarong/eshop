require "test_helper"
require "securerandom"

module Ec
  class FunnelAnomalyNotifierTest < ActiveSupport::TestCase
    self.use_transactional_tests = true

    setup do
      @token = SecureRandom.hex(6)
      @admin = User.create!(email: "funnel-notification-admin-#{@token}@example.com", password: "password123")
      @admin.roles << Role.find_by!(code: "super_admin")
      @operator = User.create!(email: "funnel-notification-operator-#{@token}@example.com", password: "password123")
      @sku = Ec::Sku.create!(sku_code: "FUNNEL-#{@token}", product_name: "Funnel SKU")
      @store = Ec::Store.create!(platform: "ozon", store_name: "Funnel store #{@token}", company_type: "small", is_active: true)
      Ec::SkuOperatorAssignment.create!(sku: @sku, user: @operator)
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
      assert_includes notification.body, "2026-10-16"
      assert_includes notification.body, "2026-10-18"
      assert_equal "2026-10-16", notification.metadata.fetch("from_date")
      assert_equal "2026-10-18", notification.metadata.fetch("to_date")
      assert @admin.system_notification_recipients.inbox.sole.notification.digest_notifications.exists?(notification.id)
      assert @operator.system_notification_recipients.inbox.sole.notification.digest_notifications.exists?(notification.id)
    end

    test "batch notifications show and link to the same settled window in all locales" do
      observations = 10.times.map do |index|
        { sku_code: "BATCH-#{@token}-#{index}", current: { views: 100, orders: 0 }, baseline: { views: 100, orders: 10 } }
      end

      %i[zh en ru].each do |locale|
        I18n.with_locale(locale) do
          Ec::FunnelAnomalyNotifier.call(observations: observations, store: @store, as_of: Date.new(2026, 10, 17))
        end

        batch = Ec::SystemNotification.where(store: @store, sku_code: nil).sole
        assert_includes batch.body, "2026-10-15"
        assert_includes batch.body, "2026-10-17"
        assert_includes batch.target_path, "from_date=2026-10-15"
        assert_includes batch.target_path, "to_date=2026-10-17"
        assert_equal "2026-10-15", batch.metadata.fetch("from_date")
        assert_equal "2026-10-17", batch.metadata.fetch("to_date")
        refute_match(/translation missing|%\{/, batch.body)
        notification = Ec::SystemNotification.where(store: @store, sku_code: observations.first.fetch(:sku_code)).sole
        assert_includes notification.body, "2026-10-15"
        assert_includes notification.body, "2026-10-17"
        refute_match(/translation missing|%\{/, notification.body)
      end
    end
  end
end
