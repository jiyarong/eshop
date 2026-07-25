require "test_helper"

class ErpAI::DynamicDailySalesForecastTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(4).upcase
    @sku = Ec::Sku.create!(sku_code: "FORECAST-#{@token}", product_name: "Forecast #{@token}")
    @date_to = Date.new(2026, 7, 24)
  end

  teardown do
    Ec::Snapshot.where(sku_id: @sku&.id).delete_all
    Ec::SkuMarketingState.where(sku_id: @sku&.id).delete_all
    Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
  end

  test "uses the rising path and caps forecast at one and a half times s7" do
    create_snapshots([ 2 ] * 8 + [ 10 ] * 7)

    result = forecast

    assert_equal 15.0, result[:forecast_daily_sales]
    assert_equal :rising, result.dig(:calculation, :path)
    assert_equal 10.0, result.dig(:calculation, :s7)
    assert_equal 2.0, result.dig(:calculation, :historical_s7)
  end

  test "uses the declining path and floors forecast at half of s30" do
    create_snapshots([ 10 ] * 8 + [ 2 ] * 7)

    result = forecast

    assert_equal :declining, result.dig(:calculation, :path)
    assert_in_delta 3.1333, result[:forecast_daily_sales], 0.0001
  end

  test "forces positive clearance momentum through the stable path" do
    @sku.marketing_states.create!(grade: "B", stage: "clr", effective_at: Time.current)
    create_snapshots([ 2 ] * 8 + [ 10 ] * 7)

    result = forecast

    assert_equal "CLR", result[:marketing_stage]
    assert_equal :stable, result.dig(:calculation, :path)
    assert_in_delta 7.1556, result[:forecast_daily_sales], 0.0001
  end

  test "removes stockout days before applying cold start average" do
    create_snapshots([ 2, 4, 100, 6, 8, 10, 12 ], stockout_indexes: [ 2 ])

    result = forecast

    assert_equal 7, result[:snapshot_days]
    assert_equal 6, result[:valid_days]
    assert_equal 1, result[:stockout_days]
    assert_equal 7.0, result[:forecast_daily_sales]
    assert_equal :cold_start, result.dig(:calculation, :path)
  end

  test "returns zero when every snapshot is a stockout day" do
    create_snapshots([ 5, 6 ], stockout_indexes: [ 0, 1 ])

    result = forecast

    assert_equal 0.0, result[:forecast_daily_sales]
    assert_equal :no_valid_days, result.dig(:calculation, :path)
  end

  private

  def forecast
    described_class.new(sku: @sku, date_to: @date_to).call
  end

  def described_class
    ErpAI::DynamicDailySalesForecast
  end

  def create_snapshots(sales, stockout_indexes: [])
    first_date = @date_to - (sales.size - 1).days
    rows = sales.each_with_index.map do |quantity, index|
      {
        snapshot_type: Ec::InventorySnapshot.snapshot_type,
        snapshot_date: first_date + index.days,
        sku_id: @sku.id,
        content: {
          overview: {
            daily_sales: quantity,
            out_of_stock: stockout_indexes.include?(index)
          }
        }
      }
    end

    Ec::Snapshot.insert_all!(rows)
  end
end
