require "test_helper"
require "securerandom"

class Ec::SkuInventoryTrendQueryTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(4).upcase
    @sku = Ec::Sku.create!(sku_code: "INV-TREND-#{@token}", product_name: "Inventory trend")
    @time_zone = ActiveSupport::TimeZone["Asia/Shanghai"]
  end

  teardown do
    Ec::OperationAction.where(ec_sku_id: @sku&.id).delete_all
    Ec::Snapshot.where(sku_id: @sku&.id).delete_all
    Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
  end

  test "uses the last valid snapshot in each week and preserves missing weeks" do
    create_snapshot(Date.new(2026, 8, 4), book_stock: 90, platform_stock: 40)
    create_snapshot(Date.new(2026, 8, 9), book_stock: 80, platform_stock: 35)
    create_snapshot(Date.new(2026, 8, 23), book_stock: 70, platform_stock: 30)

    result = query(to_date: Date.new(2026, 8, 23), weeks: 3)

    assert_equal 3, result[:weeks].size
    assert_equal Date.new(2026, 8, 9), result[:weeks][0][:snapshot_date]
    assert_equal 80, result[:weeks][0].dig(:metrics, :book_stock)
    assert result[:weeks][1][:missing]
    assert_equal Date.new(2026, 8, 23), result[:weeks][2][:snapshot_date]
  end

  test "derives fulfillment totals and cover only from the selected snapshot" do
    date = Date.new(2026, 8, 23)
    Ec::Snapshot.create!(
      sku: @sku,
      snapshot_type: Ec::InventorySnapshot.snapshot_type,
      snapshot_date: date,
      content: {
        overview: { book_stock: 60, incoming_quantity: 30, daily_sales_velocity: "3.0" },
        distribution: { levels: [
          { fulfillment_type: "fbw", quantity: 20 },
          { fulfillment_type: "fbo", quantity: 10 },
          { fulfillment_type: "fbs", quantity: 7 },
          { fulfillment_type: "inbound", quantity: 4 }
        ] }
      }
    )

    metrics = query(to_date: date, weeks: 1).dig(:weeks, 0, :metrics)

    assert_equal 30, metrics[:platform_stock]
    assert_equal 7, metrics[:fbs_stock]
    assert_equal 4, metrics[:platform_inbound_stock]
    assert_equal BigDecimal("30"), metrics[:turnover_days_with_procurement]
    assert_equal BigDecimal("20"), metrics[:turnover_days]
  end

  test "builds store trend from only the selected store levels" do
    date = Date.new(2026, 8, 23)
    Ec::Snapshot.create!(
      sku: @sku,
      snapshot_type: Ec::InventorySnapshot.snapshot_type,
      snapshot_date: date,
      content: {
        overview: { book_stock: 60 },
        distribution: { levels: [
          { platform: "ozon", store_id: 11, store_name: "Store A", account_id: 101, fulfillment_type: "fbo", quantity: 20 },
          { platform: "ozon", store_id: 11, store_name: "Store A", account_id: 101, fulfillment_type: "fbs", quantity: 5 },
          { platform: "ozon", store_id: 12, store_name: "Store B", account_id: 102, fulfillment_type: "fbo", quantity: 70 }
        ] }
      }
    )

    result = Ec::SkuInventoryTrendQuery.new(
      @sku,
      to_date: date,
      time_zone: @time_zone,
      weeks: 1,
      selected_store_key: "ozon:store:11"
    ).call

    assert_equal ["ozon:store:11", "ozon:store:12"], result[:store_options].map { |option| option[:key] }
    assert_equal "ozon:store:11", result[:selected_store_key]
    assert_equal date - 27.days, result[:store_from_date]
    assert_equal date, result[:store_to_date]
    assert_equal 28, result[:store_days].size
    assert result[:store_days].first[:missing]
    assert_equal 20, result.dig(:store_days, -1, :metrics, :platform_stock)
    assert_equal 5, result.dig(:store_days, -1, :metrics, :fbs_stock)
  end

  test "uses a custom daily store range without filling missing snapshots" do
    from_date = Date.new(2026, 8, 20)
    create_store_snapshot(from_date, quantity: 12)
    create_store_snapshot(from_date + 2.days, quantity: 7)

    result = Ec::SkuInventoryTrendQuery.new(
      @sku,
      to_date: from_date + 3.days,
      time_zone: @time_zone,
      weeks: 1,
      store_from_date: from_date,
      store_to_date: from_date + 3.days
    ).call

    assert_equal 4, result[:store_days].size
    assert_equal [12, nil, 7, nil], result[:store_days].map { |row| row.dig(:metrics, :platform_stock) }
    assert_equal [false, true, false, true], result[:store_days].map { |row| row[:missing] }
  end

  private

  def query(to_date:, weeks:)
    Ec::SkuInventoryTrendQuery.new(@sku, to_date: to_date, time_zone: @time_zone, weeks: weeks).call
  end

  def create_snapshot(date, book_stock:, platform_stock:)
    Ec::Snapshot.create!(
      sku: @sku,
      snapshot_type: Ec::InventorySnapshot.snapshot_type,
      snapshot_date: date,
      content: {
        overview: {
          book_stock: book_stock,
          platform_stock: platform_stock,
          incoming_quantity: 10,
          daily_sales_velocity: "2.0",
          turnover_days: book_stock / 2.0,
          turnover_days_with_procurement: (book_stock + 10) / 2.0
        }
      }
    )
  end

  def create_store_snapshot(date, quantity:)
    Ec::Snapshot.create!(
      sku: @sku,
      snapshot_type: Ec::InventorySnapshot.snapshot_type,
      snapshot_date: date,
      content: {
        overview: { book_stock: quantity },
        distribution: { levels: [
          { platform: "ozon", store_id: 11, store_name: "Store A", fulfillment_type: "fbo", quantity: quantity }
        ] }
      }
    )
  end
end
