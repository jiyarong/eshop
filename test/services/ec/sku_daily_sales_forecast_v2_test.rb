require "test_helper"

class Ec::SkuDailySalesForecastV2Test < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(4).upcase
    @sku = Ec::Sku.create!(sku_code: "ROLLING-FORECAST-V2-#{@token}", product_name: "Rolling forecast V2")
    @from_date = Date.new(2026, 8, 1)
    @to_date = @from_date + 27.days
  end

  teardown do
    Ec::Snapshot.where(sku_id: @sku&.id).delete_all
    Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
  end

  test "uses recent and prior weekly demand states" do
    create_snapshots(sales: [ 10 ] * 7 + [ 2 ] * 7, inventory: [ 20 ] * 14)

    result = service.forecast(as_of: @from_date + 13.days, sku_code: @sku.sku_code)
    forecast = result.fetch(@sku.sku_code)

    assert_in_delta 2.8, forecast.fetch(:daily_sales).to_f, 0.0001
    assert_equal "demand_state_weekly_blend", forecast.fetch(:formula)
    assert_equal :continuous, forecast.fetch(:demand_state)
    assert_equal BigDecimal("2"), forecast.dig(:calculation, :recent, :mean_sales)
    assert_equal BigDecimal("10"), forecast.dig(:calculation, :prior, :mean_sales)
    assert_equal BigDecimal("0.9"), forecast.dig(:calculation, :effective_recent_weight)
    assert_equal BigDecimal("2.8"), forecast.dig(:calculation, :base_demand)
  end

  test "marks intermittent demand and keeps the original service independent" do
    create_snapshots(sales: [ 0, 0, 4, 0, 0, 0, 0, 0, 0, 4, 0, 0, 0, 0 ], inventory: [ 20 ] * 14)

    forecast = service.forecast(as_of: @from_date + 13.days, sku_code: @sku.sku_code).fetch(@sku.sku_code)

    assert_equal :intermittent, forecast.fetch(:demand_state)
    assert_operator forecast.fetch(:daily_sales), :>, 0
    calculation = forecast.fetch(:calculation)
    assert_in_delta BigDecimal("2") / 14, calculation[:positive_rate], 0.000001
    assert_equal BigDecimal("4"), calculation.dig(:intermittent, :positive_sales_mean)
    assert_in_delta BigDecimal("1") / 7, calculation.dig(:intermittent, :occurrence_rate), 0.000001
    assert_equal forecast[:daily_sales], calculation[:intermittent][:daily_sales] * (1 + calculation[:uplift])
    assert_equal :weighted_mean, Ec::SkuDailySalesForecast.new(
      sku_codes: [ @sku.sku_code ], from_date: @from_date, to_date: @to_date
    ).send(:instance_variable_get, :@formula)
  end

  test "does not treat a recent stockout as zero demand after replenishment" do
    create_snapshots(sales: [ 4 ] * 7 + [ 0 ] * 7, inventory: [ 20 ] * 7 + [ 0 ] * 7)

    forecast = service.forecast(as_of: @from_date + 13.days, sku_code: @sku.sku_code).fetch(@sku.sku_code)

    assert_in_delta 4.0, forecast.fetch(:daily_sales).to_f, 0.0001
    assert_equal BigDecimal("0"), forecast.dig(:calculation, :effective_recent_weight)
    assert_equal 7, forecast.dig(:calculation, :stockout_days)
  end

  test "explains reduced recent coverage and the inventory uplift" do
    create_snapshots(sales: [ 4 ] * 7 + [ 8 ] * 3 + [ 0 ] * 4, inventory: [ 20 ] * 10 + [ 0 ] * 4)

    forecast = service(stockout_uplift_cap: 0.5).forecast(
      as_of: @from_date + 13.days, sku_code: @sku.sku_code
    ).fetch(@sku.sku_code)
    calculation = forecast.fetch(:calculation)
    weight = BigDecimal("0.9") * 3 / 7
    base = 8 * weight + 4 * (1 - weight)

    assert_equal 7, calculation.dig(:recent, :observed_days)
    assert_equal 3, calculation.dig(:recent, :valid_days)
    assert_in_delta weight, calculation[:effective_recent_weight], 0.000001
    assert_in_delta base, calculation[:base_demand], 0.000001
    assert_in_delta BigDecimal("4") / 14 * BigDecimal("0.5"), calculation[:uplift], 0.000001
    assert_in_delta base * (1 + calculation[:uplift]), forecast[:daily_sales], 0.000001
  end

  test "explains a recent-only window and observed zero sales" do
    create_snapshots(sales: [ 0 ] * 7, inventory: [ 20 ] * 7)

    forecast = service.forecast(as_of: @from_date + 6.days, sku_code: @sku.sku_code).fetch(@sku.sku_code)
    calculation = forecast.fetch(:calculation)

    assert_equal :intermittent, forecast[:demand_state]
    assert_equal 7, calculation[:missing_days]
    assert_equal 7, calculation[:valid_days]
    assert_equal 0, calculation.dig(:prior, :valid_days)
    assert_equal 1, calculation[:effective_recent_weight]
    assert_equal 0, calculation.dig(:intermittent, :positive_sales_mean)
    assert_equal 0, forecast[:daily_sales]
  end

  test "backtests real following windows and exposes V2 parameters" do
    create_snapshots(sales: [ 4 ] * 28, inventory: [ 20 ] * 28)

    result = service.backtest

    assert_equal 2, result.fetch(:prediction_count)
    assert_equal "v2", result.fetch(:parameters).fetch(:version)
    assert_equal "demand_state_weekly_blend", result.fetch(:parameters).fetch(:formula)
  end

  private

  def service(**options)
    described_class.new(
      sku_codes: [ @sku.sku_code ],
      from_date: @from_date,
      to_date: @to_date,
      include_predictions: true,
      **options
    )
  end

  def described_class
    Ec::SkuDailySalesForecastV2
  end

  def create_snapshots(sales:, inventory:)
    rows = sales.each_with_index.map do |quantity, index|
      {
        snapshot_type: Ec::InventorySnapshot.snapshot_type,
        snapshot_date: @from_date + index.days,
        sku_id: @sku.id,
        content: {
          overview: {
            daily_sales: quantity,
            platform_stock: inventory.fetch(index),
            out_of_stock: inventory.fetch(index).zero?
          }
        }
      }
    end
    Ec::Snapshot.insert_all!(rows)
  end
end
