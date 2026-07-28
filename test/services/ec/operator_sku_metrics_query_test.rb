require "test_helper"

class Ec::OperatorSkuMetricsQueryTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(4).upcase
    @sku = Ec::Sku.create!(sku_code: "OPS-#{@token}", product_name: "Operator SKU")
    @account = RawOzon::SellerAccount.create!(
      company_name: "operator-metrics-#{@token}",
      client_id: "client-#{@token}",
      api_key: "key-#{@token}",
      company_type: "small"
    )
    @store = Ec::Store.create!(
      platform: "ozon",
      store_name: "Operator Metrics #{@token}",
      company_type: "small",
      ozon_raw_account_id: @account.id,
      is_active: true
    )
    Ec::SkuProduct.create!(
      sku_code: @sku.sku_code,
      store: @store,
      product_id: "PRODUCT-#{@token}",
      platform_sku_id: "PLATFORM-#{@token}"
    )
  end

  teardown do
    Ec::OrderItem.where(store_id: @store.id).delete_all
    Ec::Order.where(store_id: @store.id).delete_all
    Ec::SkuProduct.where(store_id: @store.id).delete_all
    Ec::Store.where(id: @store.id).delete_all
    RawOzon::SellerAccount.where(id: @account.id).delete_all
    Ec::Sku.with_deleted.where(id: @sku.id).delete_all
  end

  test "sales quantities use hard sku product binding and batch both windows" do
    create_order("BOUND-#{@token}", platform_sku_id: "PLATFORM-#{@token}", sku_code: nil, quantity: 3, ordered_on: Date.new(2026, 7, 27))
    create_order("OLDER-#{@token}", platform_sku_id: "PLATFORM-#{@token}", sku_code: nil, quantity: 5, ordered_on: Date.new(2026, 7, 10))
    create_order("PREV7-#{@token}", platform_sku_id: "PLATFORM-#{@token}", sku_code: nil, quantity: 2, ordered_on: Date.new(2026, 7, 20))
    create_order("PREV30-#{@token}", platform_sku_id: "PLATFORM-#{@token}", sku_code: nil, quantity: 10, ordered_on: Date.new(2026, 6, 20))
    create_order("REDUNDANT-#{@token}", platform_sku_id: "UNBOUND-#{@token}", sku_code: @sku.sku_code, quantity: 99, ordered_on: Date.new(2026, 7, 27))

    query = Ec::OperatorSkuMetricsQuery.new(
      skus: [@sku],
      date_to: Date.new(2026, 7, 28),
      time_zone: ActiveSupport::TimeZone["Asia/Shanghai"]
    )
    sales = query.send(:sales_quantities)

    assert_equal 3, sales.dig(@sku.sku_code, :days_7, :value)
    assert_equal 10, sales.dig(@sku.sku_code, :days_30, :value)
    assert_equal 50, sales.dig(@sku.sku_code, :days_7, :comparison, :delta_pct)
    assert_equal 0, sales.dig(@sku.sku_code, :days_30, :comparison, :delta_pct)
  end

  test "profit metrics use the last natural week and last four natural weeks" do
    calls = []
    original_run = Ec::WeeklySummaryDeepQuery.method(:run)
    sku_code = @sku.sku_code
    Ec::WeeklySummaryDeepQuery.define_singleton_method(:run) do |from_date:, to_date:, sku_codes:|
      calls << [from_date, to_date, sku_codes]
      multiplier = (to_date - from_date).to_i > 7 ? 4 : 1
      comparison = { delta_pct: multiplier * 10, semantic: "positive" }
      {
        rows: [{ sku: sku_code, revenue: 100 * multiplier, after_tax: 20 * multiplier, margin_pct: 20, ads: -5 * multiplier }],
        comparison: {
          rows: {
            sku_code => %i[revenue after_tax margin_pct ads].index_with { comparison }
          }
        }
      }
    end

    query = Ec::OperatorSkuMetricsQuery.new(
      skus: [@sku],
      date_to: Date.new(2026, 7, 28),
      time_zone: ActiveSupport::TimeZone["Asia/Shanghai"]
    )
    metrics = query.send(:profit_metrics)

    assert_equal [Date.new(2026, 7, 20), Date.new(2026, 7, 26), [sku_code]], calls[0]
    assert_equal [Date.new(2026, 6, 29), Date.new(2026, 7, 26), [sku_code]], calls[1]
    assert_equal 100, metrics.dig(sku_code, :days_7, :revenue, :value)
    assert_equal 400, metrics.dig(sku_code, :days_30, :revenue, :value)
    assert_equal 10, metrics.dig(sku_code, :days_7, :revenue, :comparison, :delta_pct)
    assert_equal 40, metrics.dig(sku_code, :days_30, :revenue, :comparison, :delta_pct)
  ensure
    Ec::WeeklySummaryDeepQuery.define_singleton_method(:run, original_run)
  end

  private

  def create_order(external_id, platform_sku_id:, sku_code:, quantity:, ordered_on:)
    order = Ec::Order.create!(
      platform: "ozon",
      store: @store,
      external_order_id: external_id,
      order_key: "ozon:#{@store.id}:#{external_id}",
      order_status: "delivered",
      ordered_at: ActiveSupport::TimeZone["Asia/Shanghai"].parse("#{ordered_on} 10:00")
    )
    order.items.create!(
      platform: "ozon",
      store: @store,
      external_item_id: "#{external_id}-item",
      platform_sku_id: platform_sku_id,
      sku_code: sku_code,
      quantity: quantity
    )
  end
end
