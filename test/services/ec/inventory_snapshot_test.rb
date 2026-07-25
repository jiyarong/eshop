require "test_helper"

class Ec::InventorySnapshotTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(4).upcase
    @account_id_seed = @token.to_i(16) % 1_000_000
    @sku = Ec::Sku.create!(sku_code: "INVENTORY-SNAPSHOT-#{@token}", product_name: "Inventory snapshot test")
    Ec::SkuBatch.create!(
      sku_code: @sku.sku_code,
      batch_code: "INVENTORY-SNAPSHOT-BATCH-#{@token}",
      status: "received",
      batch_type: :normal,
      purchased_quantity: 12,
      received_quantity: 12,
      received_on: Date.new(2026, 7, 23),
      purchase_unit_price_cny: 1
    )

    Ec::SkuInventoryLevel.create!(
      sku_code: @sku.sku_code,
      platform: "wb",
      account_id: 10_000 + @account_id_seed,
      store_name: "WB #{@token}",
      fulfillment_type: "fbw",
      quantity: 4,
      is_latest: false,
      synced_at: Time.utc(2026, 7, 24, 15, 30),
      metadata: { "source" => "warehouse_remains" },
      warehouse_breakdown: [
        {
          "warehouse_name" => "Коледино",
          "warehouse_id" => 507,
          "region_name" => "Москва",
          "quantity" => 4
        }
      ]
    )
    Ec::SkuInventoryLevel.create!(
      sku_code: @sku.sku_code,
      platform: "wb",
      account_id: 10_000 + @account_id_seed,
      store_name: "WB #{@token}",
      fulfillment_type: "fbw",
      quantity: 99,
      is_latest: true,
      synced_at: Time.utc(2026, 7, 24, 16, 30),
      metadata: { "source" => "next_day" },
      warehouse_breakdown: []
    )
    Ec::SkuInventoryLevel.create!(
      sku_code: @sku.sku_code,
      platform: "ozon",
      account_id: 1_020_000 + @account_id_seed,
      store_name: "Ozon #{@token}",
      fulfillment_type: "fbo",
      quantity: 0,
      is_latest: true,
      synced_at: Time.utc(2026, 7, 24, 15, 35),
      metadata: { "source" => "stock_on_warehouses" },
      warehouse_breakdown: [
        {
          "warehouse_name" => "Пушкино_1",
          "cluster_name" => "Москва",
          "quantity" => 0,
          "promised" => 2,
          "reserved" => 1
        }
      ]
    )
  end

  teardown do
    Ec::Snapshot.where(snapshot_type: Ec::InventorySnapshot.snapshot_type, sku_id: @sku&.id).delete_all
    Ec::SkuInventoryLevel.where(sku_code: @sku&.sku_code).delete_all
    Ec::SkuBatch.where(sku_code: @sku&.sku_code).delete_all
    Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
  end

  test "captures inventory overview and complete store warehouse distribution" do
    snapshot_date = Date.new(2026, 7, 24)
    with_stubbed_sku_find_each do
      Ec::SnapshotRunner.new(snapshot_date: snapshot_date, modules: [ Ec::InventorySnapshot ]).run
    end

    snapshot = Ec::Snapshot.find_by!(
      snapshot_type: Ec::InventorySnapshot.snapshot_type,
      snapshot_date: snapshot_date,
      sku: @sku
    )
    overview = snapshot.data[:overview]
    distribution = snapshot.data.dig(:distribution, :levels)

    assert_equal 12, overview[:book_stock]
    assert_equal 4, overview[:platform_stock]
    assert_equal "0.0", overview[:daily_sales_velocity]
    assert_nil overview[:turnover_days]
    assert_nil overview[:turnover_days_with_procurement]
    assert_equal false, overview[:out_of_stock]
    assert_equal 0, overview[:daily_sales]
    assert_equal 4, overview.dig(:platform_totals, "wb", :platform_stock)
    assert_equal false, overview.dig(:platform_totals, "wb", :out_of_stock)
    assert_equal 0, overview.dig(:platform_totals, "ozon", :platform_stock)
    assert_equal true, overview.dig(:platform_totals, "ozon", :out_of_stock)

    wb_fbw = distribution.find { |level| level[:platform] == "wb" && level[:fulfillment_type] == "fbw" }
    assert_equal "warehouse_remains", wb_fbw.dig(:metadata, "source")
    assert_equal "Коледино", wb_fbw.dig(:warehouse_breakdown, 0, "warehouse_name")
    assert_equal "Москва", wb_fbw.dig(:warehouse_breakdown, 0, "region_name")

    ozon_fbo = distribution.find { |level| level[:platform] == "ozon" && level[:fulfillment_type] == "fbo" }
    assert_equal Time.utc(2026, 7, 24, 15, 35), ozon_fbo[:synced_at]
    assert_equal "Москва", ozon_fbo.dig(:warehouse_breakdown, 0, "cluster_name")
    assert_equal 2, ozon_fbo.dig(:warehouse_breakdown, 0, "promised")
    assert_equal 1, ozon_fbo.dig(:warehouse_breakdown, 0, "reserved")
  end

  test "is registered with the daily snapshot runner" do
    assert_includes Ec::SnapshotRunner::SNAPSHOT_MODULES, Ec::InventorySnapshot
  end

  test "keeps overview and omits distribution when no level existed by the snapshot date" do
    snapshot_date = Date.new(2026, 6, 20)

    with_stubbed_sku_find_each do
      Ec::SnapshotRunner.new(snapshot_date: snapshot_date, modules: [ Ec::InventorySnapshot ]).run
    end

    content = Ec::Snapshot.fetch(Ec::InventorySnapshot.snapshot_type, on: snapshot_date, sku: @sku)

    assert_equal 0, content.dig(:overview, :book_stock)
    assert_not content.key?(:distribution)
  end

  private

  def with_stubbed_sku_find_each
    singleton_class = Ec::Sku.singleton_class
    original_method = singleton_class.instance_method(:find_each)
    sku = @sku
    singleton_class.send(:define_method, :find_each) { [ sku ].each }

    yield
  ensure
    singleton_class.send(:define_method, :find_each, original_method)
  end
end
