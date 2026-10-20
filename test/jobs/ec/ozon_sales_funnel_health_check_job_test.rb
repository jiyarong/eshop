require "test_helper"

class Ec::OzonSalesFunnelHealthCheckJobTest < ActiveSupport::TestCase
  self.use_transactional_tests = true

  setup do
    token = SecureRandom.hex(6)
    @account = RawOzon::SellerAccount.create!(client_id: "funnel-health-#{token}", api_key: "test", company_type: "small")
    @store = Ec::Store.create!(platform: "ozon", store_name: "Funnel health #{token}", company_type: "small",
      is_active: true, ozon_raw_account_id: @account.id)
    @sku = Ec::Sku.create!(sku_code: "FUNNEL-HEALTH-#{token}")
    @product = Ec::SkuProduct.create!(sku: @sku, store: @store, product_id: "PRODUCT-#{token}", platform_sku_id: "1001")
    travel_to Time.utc(2026, 10, 20, 4)
  end

  teardown do
    travel_back
  end

  test "does not treat the latest two incomplete days or today as an order collapse" do
    seed_window(Date.new(2026, 10, 12)..Date.new(2026, 10, 17), orders: 4)
    seed_window(Date.new(2026, 10, 18)..Date.new(2026, 10, 20), orders: 0)

    assert_empty notifications
  end

  test "still notifies a real decline after the two day grace period" do
    seed_window(Date.new(2026, 10, 12)..Date.new(2026, 10, 14), orders: 4)
    seed_window(Date.new(2026, 10, 15)..Date.new(2026, 10, 17), orders: 0)
    seed_window(Date.new(2026, 10, 18)..Date.new(2026, 10, 20), orders: 100)

    notification = notifications.sole
    assert_equal @sku.sku_code, notification.fetch(:sku_code)
    assert_equal 300, notification.dig(:metadata, :current_views)
    assert_equal 300, notification.dig(:metadata, :baseline_views)
    assert_equal 0, notification.dig(:metadata, :current_orders)
    assert_equal 12, notification.dig(:metadata, :baseline_orders)
    assert_equal Date.new(2026, 10, 17).end_of_day, notification.fetch(:occurred_at)
  end

  test "waits when a day is missing from the current window" do
    seed_window(Date.new(2026, 10, 12)..Date.new(2026, 10, 14), orders: 4)
    seed_window([Date.new(2026, 10, 15), Date.new(2026, 10, 17)], orders: 0)

    assert_empty notifications
  end

  test "waits when a day is missing from the baseline window" do
    seed_window([Date.new(2026, 10, 12), Date.new(2026, 10, 14)], orders: 4)
    seed_window(Date.new(2026, 10, 15)..Date.new(2026, 10, 17), orders: 0)

    assert_empty notifications
  end

  test "does not fall back to stale data when the expected window is not available" do
    seed_window(Date.new(2026, 10, 11)..Date.new(2026, 10, 13), orders: 4)
    seed_window(Date.new(2026, 10, 14)..Date.new(2026, 10, 16), orders: 0)

    assert_empty notifications
  end

  test "uses the Shanghai business date at the UTC date boundary" do
    travel_to Time.utc(2026, 10, 19, 16, 30)
    seed_window(Date.new(2026, 10, 12)..Date.new(2026, 10, 14), orders: 4)
    seed_window(Date.new(2026, 10, 15)..Date.new(2026, 10, 17), orders: 0)

    assert_equal Date.new(2026, 10, 17).end_of_day, notifications.sole.fetch(:occurred_at)
  end

  test "batches daily aggregation as the number of products grows" do
    seed_window(Date.new(2026, 10, 12)..Date.new(2026, 10, 17), orders: 4)
    # Warm up model metadata before counting uncached application queries.
    measure_check
    small = measure_check
    9.times do |index|
      product = Ec::SkuProduct.create!(sku: @sku, store: @store, product_id: "BATCH-#{index}", platform_sku_id: (1002 + index).to_s)
      seed_window(Date.new(2026, 10, 12)..Date.new(2026, 10, 17), orders: 4, product: product)
    end
    large = measure_check

    assert_equal 3, large[:queries]
    assert_equal small[:queries], large[:queries]
    assert_equal small[:max_sql], large[:max_sql]
    assert_equal 20, large[:instantiated]["RawOzon::SalesFunnelDaily"]
    assert_equal 10, large[:instantiated]["Ec::SkuProduct"]
  end

  private

  def seed_window(dates, orders:, product: @product)
    dates.each do |date|
      RawOzon::SalesFunnelDaily.create!(account: @account, sku: product.platform_sku_id, stat_date: date,
        hits_view_pdp: 100, ordered_units: orders, synced_at: Time.current)
    end
  end

  def notifications
    result = []
    original = Ec::SystemNotificationDispatcher.method(:call)
    Ec::SystemNotificationDispatcher.define_singleton_method(:call, ->(**attributes) { result << attributes })
    Ec::OzonSalesFunnelHealthCheckJob.new.send(:check_store, @store)
    result
  ensure
    Ec::SystemNotificationDispatcher.define_singleton_method(:call, original) if original
  end

  def measure_check
    metrics = { queries: 0, max_sql: 0, instantiated: Hash.new(0) }
    sql = lambda do |_name, _start, _finish, _id, payload|
      next if payload[:cached] || payload[:name] == "SCHEMA"

      metrics[:queries] += 1
      metrics[:max_sql] = [metrics[:max_sql], payload[:sql].length].max
    end
    instantiated = lambda do |_name, _start, _finish, _id, payload|
      metrics[:instantiated][payload[:class_name]] += payload[:record_count]
    end
    ActiveRecord::Base.uncached do
      ActiveSupport::Notifications.subscribed(sql, "sql.active_record") do
        ActiveSupport::Notifications.subscribed(instantiated, "instantiation.active_record") { notifications }
      end
    end
    metrics
  end
end
