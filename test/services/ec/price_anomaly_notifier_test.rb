require "test_helper"
require "securerandom"

module Ec
  class PriceAnomalyNotifierTest < ActiveSupport::TestCase
    self.use_transactional_tests = true

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

    test "notifies assigned operator and admin for a large price increase" do
      Ec::PriceAnomalyNotifier.call(actions: [@action], store: @store)

      notification = Ec::SystemNotification.where(sku_code: @sku.sku_code).sole
      assert_equal "price_anomaly", notification.notification_type
      assert_equal "critical", notification.severity
      assert_includes notification.body, "10000"
      assert @admin.system_notification_recipients.inbox.sole.notification.digest_notifications.exists?(notification.id)
      assert @operator.system_notification_recipients.inbox.sole.notification.digest_notifications.exists?(notification.id)
      assert_equal "/reports/skus/#{@sku.sku_code}?tab=operation_actions", notification.target_path
    end

    test "ignores small price changes" do
      @action.update!(diff_result: { "fields" => { "marketing_price" => { "from" => "5000", "to" => "5400" } } })

      Ec::PriceAnomalyNotifier.call(actions: [@action], store: @store)

      assert_empty Ec::SystemNotification.where(sku_code: @sku.sku_code)
    end
  end
end
