require "test_helper"
require "securerandom"

class Ec::InventoryPageDetailQueryTest < ActiveSupport::TestCase
  test "builds drawer payload from overview batches and latest levels" do
    token = SecureRandom.hex(4).upcase
    sku = Ec::Sku.create!(sku_code: "DETAIL-#{token}", product_name: "详情测试商品")

    draft = Ec::SkuBatch.create!(
      sku_code: sku.sku_code,
      batch_code: "DETAIL-DRAFT-#{token}",
      status: "draft",
      batch_type: :normal,
      purchased_quantity: 4,
      received_quantity: 0,
      purchase_unit_price_cny: 1
    )
    ordered = Ec::SkuBatch.create!(
      sku_code: sku.sku_code,
      batch_code: "DETAIL-ORDERED-#{token}",
      status: "ordered",
      batch_type: :normal,
      purchased_quantity: 6,
      received_quantity: 0,
      purchase_unit_price_cny: 1
    )
    incoming = Ec::SkuBatch.create!(
      sku_code: sku.sku_code,
      batch_code: "DETAIL-IN-#{token}",
      status: "in_transit",
      batch_type: :normal,
      purchased_quantity: 9,
      received_quantity: 0,
      expected_arrival_on: Date.new(2026, 7, 20),
      purchase_unit_price_cny: 1
    )
    book = Ec::SkuBatch.create!(
      sku_code: sku.sku_code,
      batch_code: "DETAIL-BOOK-#{token}",
      status: "received",
      batch_type: :wb_fbw_offset,
      purchased_quantity: 0,
      received_quantity: -2,
      received_on: Date.new(2026, 6, 21),
      defect_offset_note: "WB offset",
      purchase_unit_price_cny: 1
    )
    closed = Ec::SkuBatch.create!(
      sku_code: sku.sku_code,
      batch_code: "DETAIL-CLOSED-#{token}",
      status: "closed",
      batch_type: :normal,
      purchased_quantity: 8,
      received_quantity: 8,
      received_on: Date.new(2026, 6, 20),
      purchase_unit_price_cny: 1
    )
    Ec::SkuInventoryLevel.create!(
      sku_code: sku.sku_code,
      platform: "wb",
      account_id: 1,
      store_name: "WB 店铺 #{token}",
      fulfillment_type: "fbw",
      quantity: 5,
      is_latest: true,
      synced_at: Time.zone.parse("2026-06-25 10:00:00"),
      metadata: {},
      warehouse_breakdown: [
        { warehouse_name: "WB Warehouse #{token}", quantity: 5 }
      ]
    )
    Ec::SkuInventoryLevel.create!(
      sku_code: sku.sku_code,
      platform: "wb",
      account_id: 1,
      store_name: "WB 店铺 #{token}",
      fulfillment_type: "fbw",
      quantity: 99,
      is_latest: false,
      synced_at: Time.zone.parse("2026-06-20 10:00:00"),
      metadata: {}
    )
    Ec::SkuInventoryLevel.create!(
      sku_code: sku.sku_code,
      platform: "ozon",
      account_id: 2,
      store_name: "Ozon 店铺 #{token}",
      fulfillment_type: "fbo",
      quantity: 3,
      is_latest: true,
      synced_at: Time.zone.parse("2026-06-26 10:00:00"),
      metadata: {},
      warehouse_breakdown: [
        { warehouse_name: "Ozon Warehouse #{token}", quantity: 2, promised: 1, reserved: 0 },
        { "warehouse_name" => "Ozon Reserve #{token}", "quantity" => 1, "promised" => 0, "reserved" => 1 }
      ]
    )
    Ec::SkuInventoryLevel.create!(
      sku_code: sku.sku_code,
      platform: "ozon",
      account_id: 2,
      store_name: "Ozon 店铺 #{token}",
      fulfillment_type: "inbound",
      quantity: 4,
      is_latest: true,
      synced_at: Time.zone.parse("2026-06-26 10:10:00"),
      metadata: {}
    )

    payload = Ec::InventoryPageDetailQuery.new(sku, detail_tab: "book", book_batch_page: 1).call
    summary = sku.inventory_overview[:summary]

    assert_equal sku.sku_code, payload[:sku_code]
    assert_equal "book", payload[:active_detail_tab]
    assert_equal 19, payload[:incoming_quantity]
    assert_equal [draft.batch_code, ordered.batch_code, incoming.batch_code], payload[:incoming_batches].map { |row| row[:batch_code] }
    assert_equal [book.batch_code, closed.batch_code], payload[:book_batches].map { |row| row[:batch_code] }
    assert_equal [
      ["ozon", "Ozon 店铺 #{token}", nil, 2, "fbo", 3, Time.zone.parse("2026-06-26 10:00:00")],
      ["ozon", "Ozon 店铺 #{token}", nil, 2, "inbound", 4, Time.zone.parse("2026-06-26 10:10:00")],
      ["wb", "WB 店铺 #{token}", nil, 1, "fbw", 5, Time.zone.parse("2026-06-25 10:00:00")]
    ], payload[:platform_breakdown].map { |row| [row[:platform], row[:store_name], row[:store_id], row[:account_id], row[:fulfillment_type], row[:quantity], row[:latest_synced_at]] }
    assert_equal 12, payload[:platform_breakdown].sum { |row| row[:quantity] }
    assert_equal Time.zone.parse("2026-06-25 10:00:00"), payload[:platform_breakdown].last[:latest_synced_at]
    assert_equal summary, payload[:summary]
    assert_equal [
      ["purchase_quantity", summary[:purchase_quantity]],
      ["wb_net_sales", 0],
      ["ozon_net_sales", 0]
    ], payload[:book_mini_stats].map { |row| [row[:key], row[:value]] }
    assert_equal [
      ["ozon_fbo", 3],
      ["ozon_inbound", 4],
      ["wb_fbo", 5],
      ["wb_inbound", 0]
    ], payload[:platform_mini_stats].map { |row| [row[:key], row[:value]] }
    assert_equal(
      { store_label_key: "summary", fbo: 8, inbound: 4, fbs: 0 },
      payload[:platform_shop_summary_row]
    )
    assert_equal "overseas_available", payload[:platform_formula][:description_key]
    assert_equal [
      { key: "book_inventory", value: summary[:book_stock], operator: "+" },
      { key: "platform_inventory_total", value: summary[:fbo_fbw_stock], operator: "-" },
      { key: "platform_inbound", value: summary[:platform_inbound_stock], operator: "-" }
    ], payload[:platform_formula][:items]
    assert_equal summary[:available_stock], payload[:platform_formula][:result]
    assert_equal [
      ["OZON * Ozon 店铺 #{token}", "fbo", "Ozon Reserve #{token}", 1, 0, 1, Time.zone.parse("2026-06-26 10:00:00")],
      ["OZON * Ozon 店铺 #{token}", "fbo", "Ozon Warehouse #{token}", 2, 1, 0, Time.zone.parse("2026-06-26 10:00:00")],
      ["WB * WB 店铺 #{token}", "fbw", "WB Warehouse #{token}", 5, nil, nil, Time.zone.parse("2026-06-25 10:00:00")]
    ], payload[:platform_warehouse_rows].map { |row| [row[:store_label], row[:fulfillment_type], row[:warehouse_name], row[:quantity], row[:promised], row[:reserved], row[:latest_synced_at]] }
  ensure
    Ec::SkuInventoryLevel.where(sku_code: sku&.sku_code).delete_all
    Ec::SkuBatch.where(sku_code: sku&.sku_code).delete_all
    Ec::Sku.with_deleted.where(sku_code: sku&.sku_code).delete_all
  end

  test "keeps daily sales velocity and turnover days only in detail overview" do
    token = SecureRandom.hex(4).upcase
    sku = Ec::Sku.create!(sku_code: "DETAIL-METRIC-#{token}", product_name: "详情指标测试商品")

    Ec::SkuBatch.create!(
      sku_code: sku.sku_code,
      batch_code: "DETAIL-METRIC-REC-#{token}",
      status: "received",
      batch_type: :normal,
      purchased_quantity: 0,
      received_quantity: 24,
      purchase_unit_price_cny: 1
    )
    Ec::SkuInventoryLevel.create!(
      sku_code: sku.sku_code,
      platform: "wb",
      account_id: 11,
      store_name: "测试店铺 #{token}",
      fulfillment_type: "fbw",
      quantity: 6,
      is_latest: true,
      synced_at: Time.zone.parse("2026-06-25 10:00:00"),
      metadata: {}
    )

    fake_velocity_factory = lambda do |sku_codes:, date_to:, time_zone:|
      Object.new.tap do |query|
        query.define_singleton_method(:call) do
          {
            sku.sku_code => { daily_sales_velocity: BigDecimal("3.2") }
          }
        end
      end
    end

    with_stubbed_constructor(Ec::InventoryVelocityMetricsQuery, fake_velocity_factory) do
      payload = Ec::InventoryPageDetailQuery.new(sku, detail_tab: "book", book_batch_page: 1).call

      assert_equal BigDecimal("3.2"), payload[:daily_sales_velocity]
      assert_in_delta 7.5, payload[:turnover_days].to_f, 0.01
      refute_includes payload[:book_mini_stats].map { |row| row[:key] }, "daily_sales_velocity"
      refute_includes payload[:book_mini_stats].map { |row| row[:key] }, "turnover_days"
      refute_includes payload[:platform_mini_stats].map { |row| row[:key] }, "daily_sales_velocity"
      refute_includes payload[:platform_mini_stats].map { |row| row[:key] }, "turnover_days"
    end
  ensure
    Ec::SkuInventoryLevel.where(sku_code: sku&.sku_code).delete_all
    Ec::SkuBatch.where(sku_code: sku&.sku_code).delete_all
    Ec::Sku.with_deleted.where(sku_code: sku&.sku_code).delete_all
  end

  test "uses supplied date and time zone for velocity metrics" do
    token = SecureRandom.hex(4).upcase
    sku = Ec::Sku.create!(sku_code: "DETAIL-TZ-#{token}", product_name: "时区测试商品")

    Ec::SkuBatch.create!(
      sku_code: sku.sku_code,
      batch_code: "DETAIL-TZ-REC-#{token}",
      status: "received",
      batch_type: :normal,
      purchased_quantity: 0,
      received_quantity: 10,
      purchase_unit_price_cny: 1
    )

    calls = []
    fake_velocity_factory = lambda do |sku_codes:, date_to:, time_zone:|
      calls << [sku_codes, date_to, time_zone.name]
      Object.new.tap do |query|
        query.define_singleton_method(:call) do
          {
            sku.sku_code => { daily_sales_velocity: BigDecimal("1.0") }
          }
        end
      end
    end

    with_stubbed_constructor(Ec::InventoryVelocityMetricsQuery, fake_velocity_factory) do
      Ec::InventoryPageDetailQuery.new(
        sku,
        detail_tab: "book",
        book_batch_page: 1,
        date_to: Date.new(2026, 7, 1),
        time_zone: ActiveSupport::TimeZone["Europe/Moscow"]
      ).call
    end

    assert_equal [[[sku.sku_code], Date.new(2026, 7, 1), "Europe/Moscow"]], calls
  ensure
    Ec::SkuInventoryLevel.where(sku_code: sku&.sku_code).delete_all
    Ec::SkuBatch.where(sku_code: sku&.sku_code).delete_all
    Ec::Sku.with_deleted.where(sku_code: sku&.sku_code).delete_all
  end

  test "clamps out of range book batch page to the actual max page" do
    token = SecureRandom.hex(4).upcase
    sku = Ec::Sku.create!(sku_code: "DETAIL-PAGE-#{token}", product_name: "分页测试商品")

    11.times do |index|
      Ec::SkuBatch.create!(
        sku_code: sku.sku_code,
        batch_code: "DETAIL-PAGE-#{token}-#{index}",
        status: "received",
        batch_type: :normal,
        purchased_quantity: 1,
        received_quantity: 1,
        purchase_unit_price_cny: 1
      )
    end

    payload = Ec::InventoryPageDetailQuery.new(sku, detail_tab: "book", book_batch_page: 999).call

    assert_equal 2, payload[:book_batch_pagination][:page]
    assert_equal 2, payload[:book_batch_pagination][:total_pages]
    assert_equal 11, payload[:book_batch_pagination][:total_count]
    assert_equal 1, payload[:book_batches].length
  ensure
    Ec::SkuInventoryLevel.where(sku_code: sku&.sku_code).delete_all
    Ec::SkuBatch.where(sku_code: sku&.sku_code).delete_all
    Ec::Sku.with_deleted.where(sku_code: sku&.sku_code).delete_all
  end

  test "builds book formula items from summary and adjustment quantities" do
    token = SecureRandom.hex(4).upcase
    sku = Ec::Sku.create!(sku_code: "DETAIL-FORMULA-#{token}", product_name: "公式测试商品")

    Ec::SkuBatch.create!(
      sku_code: sku.sku_code,
      batch_code: "DETAIL-FORMULA-NORMAL-#{token}",
      status: "received",
      batch_type: :normal,
      purchased_quantity: 10,
      received_quantity: 10,
      purchase_unit_price_cny: 1
    )
    Ec::SkuBatch.create!(
      sku_code: sku.sku_code,
      batch_code: "DETAIL-FORMULA-OFFSET-#{token}",
      status: "received",
      batch_type: :wb_fbw_offset,
      purchased_quantity: 0,
      received_quantity: -2,
      defect_offset_note: "offset",
      purchase_unit_price_cny: 1
    )

    payload = Ec::InventoryPageDetailQuery.new(sku, detail_tab: "book", book_batch_page: 1).call

    assert_includes payload[:book_formula][:items], { key: "purchase_quantity", value: 10, operator: "+" }
    assert_includes payload[:book_formula][:items], { key: "wb_fbw_offset", value: 2, operator: "-" }
    assert_equal payload[:summary][:book_stock], payload[:book_formula][:result]
  ensure
    Ec::SkuInventoryLevel.where(sku_code: sku&.sku_code).delete_all
    Ec::SkuBatch.where(sku_code: sku&.sku_code).delete_all
    Ec::Sku.with_deleted.where(sku_code: sku&.sku_code).delete_all
  end

  test "uses real order status buckets in book sales distribution" do
    token = SecureRandom.hex(4).upcase
    sku = Ec::Sku.create!(sku_code: "DETAIL-STATUS-#{token}", product_name: "状态分布测试商品")

    wb_account = RawWb::SellerAccount.create!(
      name: "wb-detail-#{token}",
      api_token: "token-#{token}",
      company_type: "small"
    )
    wb_store = Ec::Store.create!(
      platform: "wb",
      store_name: "WB 状态店 #{token}",
      company_type: "small",
      wb_raw_account_id: wb_account.id,
      is_active: true
    )
    Ec::SkuProduct.create!(
      sku_code: sku.sku_code,
      store: wb_store,
      product_id: "445566",
      platform_sku_id: "WB-DETAIL-#{token}"
    )

    processing_order = Ec::Order.create!(
      platform: "wb",
      store: wb_store,
      external_order_id: "WB-DETAIL-PROC-#{token}",
      external_order_number: "WB-DETAIL-PROC-#{token}",
      order_key: "wb:#{wb_store.id}:WB-DETAIL-PROC-#{token}",
      order_status: "processing",
      ordered_at: Time.zone.parse("2026-06-20 10:00:00"),
      synced_at: Time.zone.parse("2026-06-20 10:05:00")
    )
    processing_order.items.create!(
      platform: "wb",
      store: wb_store,
      external_item_id: "WB-DETAIL-PROC-I-#{token}",
      platform_sku_id: "445566",
      offer_id: "WB-DETAIL-OFFER-#{token}",
      product_name_source: "WB processing 商品",
      quantity: 2,
      unit_price: 50,
      payout: 100,
      commission_amount: 10,
      discount_amount: 0,
      currency_code: "BYN"
    )

    delivered_order = Ec::Order.create!(
      platform: "wb",
      store: wb_store,
      external_order_id: "WB-DETAIL-DELIV-#{token}",
      external_order_number: "WB-DETAIL-DELIV-#{token}",
      order_key: "wb:#{wb_store.id}:WB-DETAIL-DELIV-#{token}",
      order_status: "delivered",
      ordered_at: Time.zone.parse("2026-06-20 11:00:00"),
      synced_at: Time.zone.parse("2026-06-20 11:05:00")
    )
    delivered_order.items.create!(
      platform: "wb",
      store: wb_store,
      external_item_id: "WB-DETAIL-DELIV-I-#{token}",
      platform_sku_id: "445566",
      offer_id: "WB-DETAIL-OFFER-#{token}",
      product_name_source: "WB delivered 商品",
      quantity: 5,
      unit_price: 50,
      payout: 250,
      commission_amount: 10,
      discount_amount: 0,
      currency_code: "BYN"
    )

    payload = Ec::InventoryPageDetailQuery.new(sku, detail_tab: "book", book_batch_page: 1).call
    row = payload.dig(:book_sales_distribution, :rows)&.first

    assert_equal "WB * WB 状态店 #{token}", row[:store_label]
    assert_equal 0, row.dig(:counts, "pending")
    assert_equal 2, row.dig(:counts, "processing")
    assert_equal 0, row.dig(:counts, "shipping")
    assert_equal 5, row.dig(:counts, "signed")
  ensure
    Ec::OrderItem.joins(:order).where(ec_orders: { store_id: wb_store&.id }).delete_all
    Ec::OrderFulfillment.where(store_id: wb_store&.id).delete_all
    Ec::Order.where(store_id: wb_store&.id).delete_all
    Ec::SkuProduct.where(sku_code: sku&.sku_code).delete_all
    Ec::Store.where(id: wb_store&.id).delete_all
    RawWb::SellerAccount.where(id: wb_account&.id).delete_all
    Ec::SkuInventoryLevel.where(sku_code: sku&.sku_code).delete_all
    Ec::SkuBatch.where(sku_code: sku&.sku_code).delete_all
    Ec::Sku.with_deleted.where(sku_code: sku&.sku_code).delete_all
  end

  test "omits zero rows from sales and return distributions" do
    sku = Ec::Sku.create!(sku_code: "DETAIL-FILTER-#{SecureRandom.hex(4).upcase}", product_name: "过滤测试商品")

    payload = Ec::InventoryPageDetailQuery.new(sku, detail_tab: "book", book_batch_page: 1).call

    assert_equal [], payload.dig(:book_sales_distribution, :rows)
    assert_nil payload.dig(:book_sales_distribution, :summary_row)
    assert_equal [], payload.dig(:return_distribution, :rows)
    assert_nil payload.dig(:return_distribution, :summary_row)
  ensure
    Ec::SkuInventoryLevel.where(sku_code: sku&.sku_code).delete_all
    Ec::SkuBatch.where(sku_code: sku&.sku_code).delete_all
    Ec::Sku.with_deleted.where(sku_code: sku&.sku_code).delete_all
  end

  test "calculates procurement-inclusive turnover from normal procurement batches only" do
    token = SecureRandom.hex(4).upcase
    sku = Ec::Sku.create!(sku_code: "DETAIL-PROC-#{token}", product_name: "采购周转测试商品")

    Ec::SkuBatch.create!(
      sku_code: sku.sku_code,
      batch_code: "DETAIL-PROC-REC-#{token}",
      status: "received",
      batch_type: :normal,
      purchased_quantity: 0,
      received_quantity: 24,
      purchase_unit_price_cny: 1
    )
    Ec::SkuBatch.create!(
      sku_code: sku.sku_code,
      batch_code: "DETAIL-PROC-DRAFT-#{token}",
      status: "draft",
      batch_type: :normal,
      purchased_quantity: 6,
      received_quantity: 0,
      purchase_unit_price_cny: 1
    )
    Ec::SkuBatch.create!(
      sku_code: sku.sku_code,
      batch_code: "DETAIL-PROC-OFFSET-#{token}",
      status: "ordered",
      batch_type: :wb_fbw_offset,
      purchased_quantity: 50,
      received_quantity: 0,
      purchase_unit_price_cny: 1
    )

    fake_velocity_factory = lambda do |sku_codes:, date_to:, time_zone:|
      Object.new.tap do |query|
        query.define_singleton_method(:call) do
          {
            sku.sku_code => { daily_sales_velocity: BigDecimal("3.0") }
          }
        end
      end
    end

    with_stubbed_constructor(Ec::InventoryVelocityMetricsQuery, fake_velocity_factory) do
      payload = Ec::InventoryPageDetailQuery.new(sku, detail_tab: "book", book_batch_page: 1).call

      assert_in_delta 8.0, payload[:turnover_days].to_f, 0.01
      assert_in_delta 10.0, payload[:turnover_days_with_procurement].to_f, 0.01
    end
  ensure
    Ec::SkuInventoryLevel.where(sku_code: sku&.sku_code).delete_all
    Ec::SkuBatch.where(sku_code: sku&.sku_code).delete_all
    Ec::Sku.with_deleted.where(sku_code: sku&.sku_code).delete_all
  end

  private

  def with_stubbed_constructor(klass, replacement)
    singleton_class = klass.singleton_class
    original_new = singleton_class.instance_method(:new)

    singleton_class.send(:define_method, :new, &replacement)
    yield
  ensure
    singleton_class.send(:define_method, :new, original_new)
  end
end
