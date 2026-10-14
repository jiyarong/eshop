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
  end

  test "marks intermittent demand and keeps the original service independent" do
    create_snapshots(sales: [ 0, 0, 4, 0, 0, 0, 0, 0, 0, 4, 0, 0, 0, 0 ], inventory: [ 20 ] * 14)

    forecast = service.forecast(as_of: @from_date + 13.days, sku_code: @sku.sku_code).fetch(@sku.sku_code)

    assert_equal :intermittent, forecast.fetch(:demand_state)
    assert_operator forecast.fetch(:daily_sales), :>, 0
    assert_equal :weighted_mean, Ec::SkuDailySalesForecast.new(
      sku_codes: [ @sku.sku_code ], from_date: @from_date, to_date: @to_date
    ).send(:instance_variable_get, :@formula)
  end

  test "does not treat a recent stockout as zero demand after replenishment" do
    create_snapshots(sales: [ 4 ] * 7 + [ 0 ] * 7, inventory: [ 20 ] * 7 + [ 0 ] * 7)

    forecast = service.forecast(as_of: @from_date + 13.days, sku_code: @sku.sku_code).fetch(@sku.sku_code)

    assert_in_delta 4.0, forecast.fetch(:daily_sales).to_f, 0.0001
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
