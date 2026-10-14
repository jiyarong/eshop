require "test_helper"

class Ec::SkuDailySalesForecastTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(4).upcase
    @sku = Ec::Sku.create!(sku_code: "ROLLING-FORECAST-#{@token}", product_name: "Rolling forecast")
    @from_date = Date.new(2026, 8, 1)
    @to_date = @from_date + 27.days
  end

  teardown do
    Ec::Snapshot.where(sku_id: @sku&.id).delete_all
    Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
  end

  test "forecasts from a sliding local window and uses the historical inventory" do
    create_snapshots(sales: [ 2 ] * 7 + [ 10 ] * 7, inventory: [ 20 ] * 14)

    result = service(training_weeks: 1).forecast(as_of: @from_date + 13.days, sku_code: @sku.sku_code)

    assert_in_delta 10.0, result.fetch(@sku.sku_code).fetch(:daily_sales).to_f, 0.0001
    assert_equal 7, result.fetch(@sku.sku_code).fetch(:training_days)
    assert_equal 7, result.fetch(@sku.sku_code).fetch(:inventory_days)
  end

  test "backtests every rolling fold against the following real days" do
    create_snapshots(sales: [ 4 ] * 28, inventory: [ 20 ] * 28)

    result = service(training_weeks: 1, horizon_days: 7, step_days: 7).backtest

    assert_equal 1, result.fetch(:eligible_sku_count)
    assert_equal 3, result.fetch(:fold_count)
    assert_equal 3, result.fetch(:prediction_count)
    assert_equal BigDecimal("1.0"), result.dig(:overall, :accuracy_rate)
    assert_equal BigDecimal("0.0"), result.dig(:overall, :wape)
    assert result.dig(:overall, :meets_target)
    assert_equal BigDecimal("1.0"), result.dig(:overall, :sku_accuracy_rate)
    assert_equal BigDecimal("1.0"), result.dig(:overall, :observed_prediction_coverage_rate)
    assert_equal 3, result.dig(:skus, 0, :fold_count)
  end

  test "excludes zero inventory days and reports accuracy by SKU" do
    create_snapshots(sales: [ 20 ] + [ 4 ] * 27, inventory: [ 0 ] + [ 20 ] * 27)

    result = service(training_weeks: 1, horizon_days: 7, step_days: 7).backtest

    assert_equal 3, result.fetch(:prediction_count)
    assert_equal [ 6, 7, 7 ], result.fetch(:predictions).map { |prediction| prediction.fetch(:inventory_days) }
    assert_equal 3, result.dig(:skus, 0, :fold_count)
  end

  test "does not score a future window when local history is missing" do
    create_snapshots(sales: [ 4 ] * 14, inventory: [ 20 ] * 14)

    result = service(training_weeks: 1, horizon_days: 7, step_days: 7).backtest

    assert_equal 1, result.fetch(:prediction_count)
    assert_equal BigDecimal("0.3333"), result.dig(:overall, :observed_prediction_coverage_rate)
  end

  test "supports historical velocity as an explicit optional forecast input" do
    create_snapshots(sales: [ 4 ] * 14, inventory: [ 20 ] * 14, velocity: [ 12 ] * 14)

    forecast = service(formula: :ewma, velocity_weight: 1).forecast(
      as_of: @from_date + 13.days,
      sku_code: @sku.sku_code
    ).fetch(@sku.sku_code)

    assert_in_delta 12.0, forecast.fetch(:daily_sales).to_f, 0.0001
    assert_equal "ewma", service(formula: :ewma).backtest.fetch(:parameters).fetch(:formula)
    assert_equal BigDecimal("0.8"), service.backtest.dig(:parameters, :target_accuracy)
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
    Ec::SkuDailySalesForecast
  end

  def create_snapshots(sales:, inventory:, velocity: nil, stage: nil)
    rows = sales.each_with_index.map do |quantity, index|
      overview = {
        daily_sales: quantity,
        platform_stock: inventory.fetch(index),
        out_of_stock: inventory.fetch(index).zero?
      }
      overview[:daily_sales_velocity] = velocity.fetch(index) if velocity
      overview[:marketing_stage] = stage.fetch(index) if stage
      {
        snapshot_type: Ec::InventorySnapshot.snapshot_type,
        snapshot_date: @from_date + index.days,
        sku_id: @sku.id,
        content: { overview: overview }
      }
    end
    Ec::Snapshot.insert_all!(rows)
  end
end
