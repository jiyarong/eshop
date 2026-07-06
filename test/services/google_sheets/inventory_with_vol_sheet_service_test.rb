require "test_helper"

class GoogleSheets::InventoryWithVolSheetServiceTest < ActiveSupport::TestCase
  def setup
    @sku_codes = []
    @store_ids = []
    @original_base_initialize = GoogleSheets::BaseService.instance_method(:initialize)
    GoogleSheets::BaseService.define_method(:initialize) { nil }
  end

  def teardown
    GoogleSheets::BaseService.define_method(:initialize, @original_base_initialize)
    Ec::SkuCost.where(sku_code: @sku_codes).delete_all
    Ec::SkuInventoryLevel.where(sku_code: @sku_codes).delete_all
    Ec::SkuBatch.where(sku_code: @sku_codes).delete_all
    Ec::Store.where(id: @store_ids).delete_all
    Ec::Sku.with_deleted.where(sku_code: @sku_codes).delete_all
  end

  test "writes bilingual headers and flattened inventory rows to Inventory With Vol" do
    sku = create_inventory_sku("GS-INV-1")

    service = GoogleSheets::InventoryWithVolSheetService.new
    writes = []
    ensured_tab = nil
    cleared_range = nil
    batch_updates = []

    service.define_singleton_method(:ensure_sheet_exists) { |tab| ensured_tab = tab }
    service.define_singleton_method(:clear_sheet) { |range:| cleared_range = range }
    service.define_singleton_method(:sheet_id) { |_tab| 321 }
    service.define_singleton_method(:batch_update) { |requests| batch_updates << requests }
    service.define_singleton_method(:write_to_sheet) do |range:, values:|
      writes << { range: range, values: values }
    end

    fake_velocity_factory = lambda do |sku_codes:, date_to:, time_zone:|
      Object.new.tap do |query|
        query.define_singleton_method(:call) do
          {
            sku.sku_code => { daily_sales_velocity: BigDecimal("2.5") }
          }
        end
      end
    end

    with_stubbed_constructor(Ec::InventoryVelocityMetricsQuery, fake_velocity_factory) do
      result = service.call

      assert_equal "Inventory With Vol", ensured_tab
      assert_equal "Inventory With Vol!A:ZZ", cleared_range
      assert_equal({ tab: "Inventory With Vol", sku_count: 1 }, result)

      write = writes.find { |entry| entry[:range] == "Inventory With Vol!A1" }
      assert write, "expected main sheet write"

      values = write[:values]
      assert_equal "SKU", values[0][0]
      assert_equal "商品名(中文)", values[0][1]
      assert_equal "采购中库存体积(m³)", values[0][4]
      assert_equal "周转天数(含采购)", values[0][13]
      assert_equal "单件体积(L)", values[0][17]

      assert_equal "SKU", values[1][0]
      assert_equal "Название (кит.)", values[1][1]
      assert_equal "Объём закупаемого запаса (м³)", values[1][4]
      assert_equal "Оборачиваемость с закупкой", values[1][13]
      assert_equal "Объём единицы (L)", values[1][17]

      row = values[2]
      assert_equal sku.sku_code, row[0]
      assert_equal "库存导出商品", row[1]
      assert_equal "Складской товар", row[2]
      assert_equal 15, row[3]
      assert_equal BigDecimal("0.09"), row[4]
      assert_equal 20, row[5]
      assert_equal BigDecimal("0.12"), row[6]
      assert_equal 7, row[7]
      assert_equal BigDecimal("0.042"), row[8]
      assert_equal 13, row[9]
      assert_equal BigDecimal("0.078"), row[10]
      assert_equal BigDecimal("2.5"), row[11]
      assert_equal BigDecimal("8"), row[12]
      assert_equal BigDecimal("14"), row[13]
      assert_equal BigDecimal("10"), row[14]
      assert_equal BigDecimal("20"), row[15]
      assert_equal BigDecimal("30"), row[16]
      assert_equal BigDecimal("6.0"), row[17]

      assert_equal 1, batch_updates.size
    end
  end

  test "leaves cubic meter cells blank when unit volume is unavailable" do
    sku = Ec::Sku.create!(
      sku_code: "GS-INV-BLANK",
      product_name: "空体积商品",
      is_active: true
    )
    @sku_codes << sku.sku_code

    Ec::SkuBatch.create!(
      sku_code: sku.sku_code,
      batch_code: "GS-INV-BLANK-BATCH",
      status: "received",
      batch_type: :normal,
      purchased_quantity: 6,
      received_quantity: 6,
      purchase_unit_price_cny: 1
    )

    service = GoogleSheets::InventoryWithVolSheetService.new
    writes = []

    service.define_singleton_method(:ensure_sheet_exists) { |_tab| nil }
    service.define_singleton_method(:clear_sheet) { |range:| range }
    service.define_singleton_method(:sheet_id) { |_tab| 321 }
    service.define_singleton_method(:batch_update) { |_requests| nil }
    service.define_singleton_method(:write_to_sheet) do |range:, values:|
      writes << { range: range, values: values }
    end

    fake_velocity_factory = lambda do |sku_codes:, date_to:, time_zone:|
      Object.new.tap do |query|
        query.define_singleton_method(:call) do
          {
            sku.sku_code => { daily_sales_velocity: BigDecimal("1.2") }
          }
        end
      end
    end

    with_stubbed_constructor(Ec::InventoryVelocityMetricsQuery, fake_velocity_factory) do
      service.call
    end

    row = writes.find { |entry| entry[:range] == "Inventory With Vol!A1" }[:values][2]
    assert_nil row[4]
    assert_nil row[6]
    assert_nil row[8]
    assert_nil row[10]
    assert_nil row[14]
    assert_nil row[15]
    assert_nil row[16]
    assert_nil row[17]
  end

  private

  def create_inventory_sku(code)
    @sku_codes << code
    sku = Ec::Sku.create!(
      sku_code: code,
      product_name: "库存导出商品",
      product_name_ru: "Складской товар",
      is_active: true
    )
    store = Ec::Store.create!(
      platform: "ozon",
      store_name: "库存导出店铺 #{code}",
      company_type: "small",
      is_active: true
    )
    @store_ids << store.id

    Ec::SkuCost.create!(
      sku_code: code,
      pkg_length_cm: 10,
      pkg_width_cm: 20,
      pkg_height_cm: 30
    )

    Ec::SkuBatch.create!(
      sku_code: code,
      batch_code: "#{code}-REC",
      status: "received",
      batch_type: :normal,
      purchased_quantity: 20,
      received_quantity: 20,
      purchase_unit_price_cny: 1
    )
    Ec::SkuBatch.create!(
      sku_code: code,
      batch_code: "#{code}-ORDERED",
      status: "ordered",
      batch_type: :normal,
      purchased_quantity: 15,
      received_quantity: 0,
      purchase_unit_price_cny: 1
    )
    Ec::SkuInventoryLevel.create!(
      sku_code: code,
      platform: "ozon",
      account_id: store.id,
      store: store,
      store_name: store.store_name,
      fulfillment_type: "fbo",
      quantity: 7,
      is_latest: true,
      synced_at: Time.zone.parse("2026-07-04 10:00:00"),
      metadata: {}
    )

    sku
  end

  def with_stubbed_constructor(klass, replacement)
    simple_stubs = ActiveSupport::Testing::SimpleStubs.new
    simple_stubs.stub_object(klass, :new, &replacement)
    yield
  ensure
    simple_stubs&.unstub_all!
  end
end
