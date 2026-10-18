require "test_helper"

class Ec::PalletPlans::BaseStockQueryTest < ActiveSupport::TestCase
  self.use_transactional_tests = true

  setup do
    @token = SecureRandom.hex(6).upcase
    @sku = Ec::Sku.create!(sku_code: "PALLET-BASE-#{@token}")
    @ozon = Ec::Store.create!(platform: "ozon", store_name: "Pallet Ozon #{@token}", company_type: "general", ozon_raw_account_id: rand(100_000_000))
    @wb = Ec::Store.create!(platform: "wb", store_name: "Pallet WB #{@token}", company_type: "general", wb_raw_account_id: rand(100_000_000))
  end

  test "matches current own-side inventory across stores and excludes fbs and old snapshots" do
    Ec::SkuBatch.create!(sku: @sku, batch_code: "PALLET-BASE-#{@token}", status: "received",
      purchased_quantity: 100, received_quantity: 100, purchase_unit_price_cny: 1)
    product = Ec::SkuProduct.create!(sku: @sku, store: @ozon, product_id: "PRODUCT-#{@token}", platform_sku_id: "PLATFORM-#{@token}")
    order = Ec::Order.create!(platform: "ozon", store: @ozon, order_key: "pallet-base-#{@token}",
      order_status: "delivered", ordered_at: 2.days.ago)
    order.items.create!(platform: "ozon", store: @ozon, platform_sku_id: product.platform_sku_id, quantity: 12)
    inventory(@sku, @ozon, "fbo", 10)
    inventory(@sku, @ozon, "inbound", 5)
    inventory(@sku, @wb, "fbw", 7)
    inventory(@sku, @ozon, "fbs", 500)
    inventory(@sku, @ozon, "fbo", 600, is_latest: false)

    result = Ec::PalletPlans::BaseStockQuery.new(sku_codes: [@sku.sku_code.downcase, @sku.sku_code]).call

    assert_equal({ @sku.sku_code => 66 }, result)
    assert_equal @sku.inventory_overview.dig(:summary, :available_stock), result.fetch(@sku.sku_code)
  end

  test "preserves negative stock and unknown SKU returns zero" do
    inventory(@sku, @ozon, "fbo", 10)

    result = Ec::PalletPlans::BaseStockQuery.new(sku_codes: [@sku.sku_code, "NO-SUCH-#{@token}"]).call

    assert_equal(-10, result.fetch(@sku.sku_code))
    assert_equal 0, result.fetch("NO-SUCH-#{@token}")
    assert_equal @sku.inventory_overview.dig(:summary, :available_stock), result.fetch(@sku.sku_code)
    assert_empty Ec::PalletPlans::BaseStockQuery.new(sku_codes: []).call
  end

  test "batch aggregate query count does not grow with sku count or instantiate inventory rows" do
    small = measure { Ec::PalletPlans::BaseStockQuery.new(sku_codes: [@sku.sku_code]).call }
    codes = Array.new(20) { |index| "PALLET-SCALE-#{index}-#{@token}" }
    Ec::Sku.insert_all!(codes.map { |code| { sku_code: code, created_at: Time.current, updated_at: Time.current } })
    large = measure { Ec::PalletPlans::BaseStockQuery.new(sku_codes: codes).call }

    assert_equal small[:queries], large[:queries]
    assert_equal 0, large[:inventory_records]
  end

  private

  def inventory(sku, store, fulfillment_type, quantity, is_latest: true)
    Ec::SkuInventoryLevel.create!(sku: sku, store: store, platform: store.platform,
      account_id: store.ozon? ? store.ozon_raw_account_id : store.wb_raw_account_id,
      fulfillment_type: fulfillment_type, quantity: quantity, synced_at: Time.current, is_latest: is_latest)
  end

  def measure
    counts = { queries: 0, inventory_records: 0 }
    sql = lambda do |_name, _start, _finish, _id, payload|
      counts[:queries] += 1 unless payload[:cached] || payload[:name].in?(%w[SCHEMA TRANSACTION])
    end
    instantiation = lambda do |_name, _start, _finish, _id, payload|
      counts[:inventory_records] += payload[:record_count] if payload[:class_name] == "Ec::SkuInventoryLevel"
    end
    ActiveRecord::Base.uncached do
      ActiveSupport::Notifications.subscribed(sql, "sql.active_record") do
        ActiveSupport::Notifications.subscribed(instantiation, "instantiation.active_record") { yield }
      end
    end
    counts
  end
end
