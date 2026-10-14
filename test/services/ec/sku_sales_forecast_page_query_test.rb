require "test_helper"

class Ec::SkuSalesForecastPageQueryTest < ActiveSupport::TestCase
  setup do
    @sku = Ec::Sku.create!(sku_code: "FORECAST-PAGE-#{SecureRandom.hex(4).upcase}", product_name: "Forecast page")
    @from_date = Date.new(2026, 8, 1)
    @to_date = @from_date + 55.days
    @store = Ec::Store.create!(platform: "wb", store_name: "Forecast page store", company_type: "small")
    Ec::SkuProduct.create!(sku_code: @sku.sku_code, store: @store, platform: "wb", product_id: "12345")
    order = Ec::Order.create!(
      platform: "wb", store: @store, order_key: "forecast-page-#{@sku.id}",
      external_order_id: "forecast-page-#{@sku.id}", order_status: "delivered",
      ordered_at: @from_date.in_time_zone("Asia/Shanghai").noon
    )
    order.items.create!(
      platform: "wb", store: @store, platform_sku_id: "12345", quantity: 2,
      unit_price: 100, buyer_paid_unit_price: 90, currency_code: "RUB",
      buyer_currency_code: "RUB", external_item_id: "forecast-page-item-#{@sku.id}"
    )
    recent_order = Ec::Order.create!(
      platform: "wb", store: @store, order_key: "forecast-page-recent-#{@sku.id}",
      external_order_id: "forecast-page-recent-#{@sku.id}", order_status: "delivered",
      ordered_at: (@from_date + 40.days).in_time_zone("Asia/Shanghai").noon
    )
    recent_order.items.create!(
      platform: "wb", store: @store, platform_sku_id: "12345", quantity: 30,
      unit_price: 100, buyer_paid_unit_price: 90, currency_code: "RUB",
      buyer_currency_code: "RUB", external_item_id: "forecast-page-recent-item-#{@sku.id}"
    )
    Ec::Snapshot.insert_all!(56.times.map do |index|
      {
        snapshot_type: Ec::InventorySnapshot.snapshot_type,
        snapshot_date: @from_date + index.days,
        sku_id: @sku.id,
        content: {
          overview: {
            daily_sales: index < 14 ? 2 : 4,
            daily_sales_velocity: 3,
            platform_stock: index.zero? ? 0 : 20,
            book_stock: 30,
            out_of_stock: index.zero?
          }
        }
      }
    end)
  end

  teardown do
    Ec::OrderItem.where(store_id: @store&.id).delete_all if @store
    Ec::Order.where(store_id: @store&.id).delete_all if @store
    Ec::Snapshot.where(sku_id: @sku&.id).delete_all if @sku
    Ec::SkuProduct.where(sku_code: @sku&.sku_code).delete_all if @sku
    Ec::Store.where(id: @store.id).delete_all if @store
    Ec::Sku.with_deleted.where(id: @sku.id).delete_all if @sku
  end

  test "combines four forecast values with historical facts and backtests" do
    result = described_class.new(
      sku: @sku,
      from_date: @from_date,
      to_date: @to_date,
      as_of_date: @from_date + 40.days
    ).call

    assert_equal @from_date, result.dig(:period, :from)
    assert_equal 56, result.fetch(:timeline).size
    assert_equal BigDecimal("2.9429"), result.dig(:forecasts, :simple, :daily_sales)
    assert_equal BigDecimal("3.9111"), result.dig(:forecasts, :strict, :daily_sales)
    assert_equal BigDecimal("2"), result.dig(:timeline, 0, :actual_sales)
    assert result.dig(:timeline, 0, :out_of_stock)
    assert_equal BigDecimal("90"), result.dig(:timeline, 0, :price)
    assert result.fetch(:backtests).any?
    assert result.dig(:forecasts, :version_1, :daily_sales).present?
    assert result.dig(:forecasts, :version_2, :daily_sales).present?
    assert_equal 28, result.dig(:forecasts, :version_1, :training_days)
    assert_equal 28, result.dig(:forecasts, :version_1, :inventory_days)
    assert_equal 28, result.dig(:forecasts, :version_2, :training_days)
    assert_equal 28, result.dig(:forecasts, :version_2, :inventory_days)
  end

  private

  def described_class
    Ec::SkuSalesForecastPageQuery
  end
end
