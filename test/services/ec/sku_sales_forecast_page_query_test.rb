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
      as_of_date: @from_date + 40.days
    ).call

    assert_equal @from_date - 15.days, result.dig(:period, :from)
    assert_equal @from_date + 47.days, result.dig(:period, :to)
    assert_equal 63, result.fetch(:timeline).size
    assert_equal BigDecimal("2.9429"), result.dig(:forecasts, :simple, :daily_sales)
    assert_equal BigDecimal("3.9111"), result.dig(:forecasts, :strict, :daily_sales)
    first_snapshot = result.fetch(:timeline).find { |row| row[:date] == @from_date }
    assert_equal BigDecimal("2"), first_snapshot[:actual_sales]
    assert first_snapshot[:out_of_stock]
    assert_equal BigDecimal("90"), first_snapshot[:price]
    assert result.fetch(:backtests).any?
    assert result.dig(:forecasts, :version_1, :daily_sales).present?
    assert result.dig(:forecasts, :version_2, :daily_sales).present?
    assert_equal 28, result.dig(:forecasts, :version_1, :training_days)
    assert_equal 28, result.dig(:forecasts, :version_1, :inventory_days)
    assert_equal 28, result.dig(:forecasts, :version_2, :training_days)
    assert_equal 28, result.dig(:forecasts, :version_2, :inventory_days)
    assert_equal @from_date + 13.days, result.dig(:forecasts, :version_1, :calculation, :from)
    assert_equal @from_date + 40.days, result.dig(:forecasts, :version_2, :calculation, :to)
    assert result[:backtests].all? { |row| row[:target_to] <= result.dig(:period, :as_of) }
  end

  test "moves the entire history window with the forecast cutoff" do
    [ @from_date + 20.days, @to_date ].each do |as_of|
      result = described_class.new(sku: @sku, as_of_date: as_of).call

      assert_equal as_of - 55.days, result.dig(:period, :from)
      assert_equal as_of + 7.days, result.dig(:period, :to)
      assert_equal (as_of - 55.days..as_of + 7.days).to_a, result[:timeline].map { |row| row[:date] }
      %i[version_1 version_2].each do |version|
        calculation = result.dig(:forecasts, version, :calculation)
        assert_equal as_of - 27.days, calculation[:from]
        assert_equal as_of, calculation[:to]
      end
    end
  end

  test "caps followup history at today without changing forecasts or backtests" do
    as_of = @to_date - 5.days
    cutoff_report = travel_to(as_of.in_time_zone("Asia/Shanghai").noon) do
      described_class.new(sku: @sku, as_of_date: as_of).call
    end
    today = as_of + 3.days
    expanded_report = travel_to(today.in_time_zone("Asia/Shanghai").noon) do
      described_class.new(sku: @sku, as_of_date: as_of).call
    end

    assert_equal as_of, cutoff_report.dig(:period, :to)
    assert_equal 56, cutoff_report[:timeline].size
    assert_equal today, expanded_report.dig(:period, :to)
    assert_equal 59, expanded_report[:timeline].size
    assert_equal today, expanded_report[:timeline].last[:date]
    assert_equal BigDecimal("4"), expanded_report[:timeline].last[:actual_sales]
    assert_equal BigDecimal("20"), expanded_report[:timeline].last[:inventory]
    assert_equal cutoff_report[:timeline], expanded_report[:timeline].first(56)
    assert_equal cutoff_report[:forecasts], expanded_report[:forecasts]
    assert_equal cutoff_report[:backtests], expanded_report[:backtests]
  end

  test "caps followup history using the requested time zone" do
    travel_to Time.utc(2026, 8, 25, 20) do
      result = described_class.new(sku: @sku, as_of_date: Date.new(2026, 8, 24), time_zone: "UTC").call

      assert_equal Date.new(2026, 8, 25), result.dig(:period, :to)
      assert_equal Date.new(2026, 8, 25), result[:timeline].last[:date]
    end
  end

  private

  def described_class
    Ec::SkuSalesForecastPageQuery
  end
end
