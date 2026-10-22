require "test_helper"

class Ec::PalletPlans::ListingSelectionTest < ActiveSupport::TestCase
  self.use_transactional_tests = true

  setup do
    @token = SecureRandom.hex(6).upcase
    @store = Ec::Store.create!(platform: "ozon", store_name: "Listing selection #{@token}", company_type: "general")
    @sku = Ec::Sku.create!(sku_code: "LISTING-#{@token}")
  end

  test "retains a single listing and prefers the only active listing without querying orders" do
    inactive = create_product(is_active: false)
    active = create_product
    create_order(inactive, at: Time.zone.parse("2026-10-21 12:00:00"))
    queries = []
    subscriber = ->(event) { queries << event.payload[:sql] unless event.payload[:cached] }

    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      ActiveRecord::Base.uncached do
        assert_equal inactive, select_listings([inactive]).fetch(@sku.sku_code)
        assert_equal active, select_listings([inactive, active]).fetch(@sku.sku_code)
        assert_empty select_listings([])
      end
    end
    assert_empty queries
  end

  test "uses the most recent order among active listings even when an inactive listing has a newer order" do
    older, newer = create_product, create_product
    inactive = create_product(is_active: false)
    create_order(older, at: Time.zone.parse("2026-10-01 12:00:00"))
    create_order(newer, at: Time.zone.parse("2026-10-20 12:00:00"))
    create_order(newer, at: Time.zone.parse("2026-09-01 12:00:00"))
    create_order(inactive, at: Time.zone.parse("2026-10-21 12:00:00"))

    assert_equal newer, select_listings([newer, older]).fetch(@sku.sku_code)
    assert_equal newer, select_listings([inactive, older, newer]).fetch(@sku.sku_code)
  end

  test "matches orders by store platform and platform SKU rather than the redundant internal SKU" do
    ordered, unproven = create_product, create_product
    create_order(ordered, at: Time.zone.parse("2026-10-01 12:00:00"), sku_code: nil)
    other_store = Ec::Store.create!(platform: "ozon", store_name: "Other #{@token}", company_type: "general")
    wb_store = Ec::Store.create!(platform: "wb", store_name: "WB #{@token}", company_type: "general")
    create_order(unproven, at: Time.zone.parse("2026-10-21 12:00:00"), store: other_store)
    create_order(unproven, at: Time.zone.parse("2026-10-21 12:00:00"), store: wb_store)
    create_order(unproven, at: Time.zone.parse("2026-10-21 12:00:00"), platform: "wb")
    create_order(unproven, at: Time.zone.parse("2026-10-21 12:00:00"), platform_sku_id: "UNBOUND")

    assert_equal ordered, select_listings([ordered, unproven]).fetch(@sku.sku_code)
  end

  test "keeps listings unresolved when none are active none have orders or the latest order times tie" do
    first, second = create_product, create_product
    assert_nil select_listings([first, second]).fetch(@sku.sku_code)

    [first, second].each { |product| create_order(product, at: Time.zone.parse("2026-10-21 12:00:00")) }
    assert_nil select_listings([first, second]).fetch(@sku.sku_code)

    first.update!(is_active: false)
    second.update!(is_active: false)
    assert_nil select_listings([first, second]).fetch(@sku.sku_code)
  end

  test "aggregates latest orders once for a batch without instantiating order records" do
    products = []
    expected = {}
    query_counts = []
    [1, 12].each do |size|
      while expected.size < size
        sku = expected.empty? ? @sku : Ec::Sku.create!(sku_code: "LISTING-#{@token}-#{expected.size}")
        first, second = create_product(sku: sku), create_product(sku: sku)
        create_order(first, at: Time.zone.parse("2026-10-01 12:00:00"))
        create_order(second, at: Time.zone.parse("2026-10-21 12:00:00"))
        products.concat([first, second])
        expected[sku.sku_code] = second
      end
      queries = []
      record_count = 0
      sql_subscriber = ->(event) { queries << event.payload[:sql] unless event.payload[:cached] }
      record_subscriber = ->(event) { record_count += event.payload[:record_count] }
      result = nil
      ActiveSupport::Notifications.subscribed(sql_subscriber, "sql.active_record") do
        ActiveSupport::Notifications.subscribed(record_subscriber, "instantiation.active_record") do
          ActiveRecord::Base.uncached { result = select_listings(products) }
        end
      end
      assert_equal expected, result
      assert_equal 0, record_count
      assert_equal 1, queries.size
      assert_operator queries.map(&:length).max, :<, 3000
      query_counts << queries.size
    end
    assert_equal query_counts.first, query_counts.last
  end

  private

  def select_listings(products)
    Ec::PalletPlans::ListingSelection.new(products: products).call
  end

  def create_product(sku: @sku, is_active: true)
    key = SecureRandom.hex(6)
    Ec::SkuProduct.create!(sku: sku, store: @store, product_id: key, platform_sku_id: "PLATFORM-#{key}", is_active: is_active)
  end

  def create_order(product, at:, store: @store, platform: store.platform, platform_sku_id: product.platform_sku_id, sku_code: @sku.sku_code)
    order = Ec::Order.create!(platform: platform, store: store, order_key: "listing-#{SecureRandom.hex(6)}",
      order_status: "delivered", ordered_at: at)
    order.items.create!(platform: platform, store: store, platform_sku_id: platform_sku_id, sku_code: sku_code, quantity: 1)
  end
end
