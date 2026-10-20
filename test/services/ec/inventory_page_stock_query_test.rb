require "test_helper"
require_relative "../../support/book_ledger_fixtures"

class Ec::InventoryPageStockQueryTest < ActiveSupport::TestCase
  include BookLedgerFixtures

  setup { setup_ledger_world }
  teardown { teardown_ledger_world }

  test "batch inputs preserve complete rows including physical stock reconciliation" do
    ledger_batch(50)
    ledger_batch(-4, type: :wb_fbw_offset)
    ledger_batch(-3, type: :physical_stocktake_adjustment)
    ledger_batch(7, status: "draft").update!(received_quantity: 0)
    ledger_batch(9, status: "ordered").update!(received_quantity: 2)
    ledger_batch(5, status: "in_transit").update!(received_quantity: 0)
    ledger_batch(20, type: :other, status: "ordered")
    ledger_order(platform: "wb", status: "delivered", quantity: 10)
    ledger_order(platform: "wb", status: "processing", quantity: 6, ordered_at: 100.days.ago)
    returned = ledger_order(platform: "ozon", status: "delivered", quantity: 4)
    ledger_return(returned, source_status: "ReceivedBySeller", quantity: 3)
    platform_level("ozon", "fbo", 8)
    platform_level("wb", "fbw", 5)
    platform_level("ozon", "inbound", 4)
    platform_level("ozon", "fbs", 90)
    platform_level("ozon", "fbo", 100, latest: false)

    stock = Ec::InventoryPageStockQuery.new(sku_codes: [ @sku.sku_code.downcase, @sku.sku_code ]).call
    assert_equal [ @sku.sku_code ], stock.keys
    input = stock.fetch(@sku.sku_code)
    assert_equal 14, input[:incoming_quantity]
    assert_equal 35, input.dig(:summary, :book_stock)
    assert_equal 18, input.dig(:summary, :available_stock)
    assert_equal 46, input.dig(:summary, :received_quantity)

    [ false, true ].each do |physical|
      expected = Ec::InventoryPageRowQuery.new(@sku, include_expected_physical_stock: physical).call
      actual = Ec::InventoryPageRowQuery.new(@sku, stock: input, include_expected_physical_stock: physical).call
      assert_equal expected, actual
    end
  end

  test "query count stays bounded as the number of skus grows" do
    order = ledger_order(platform: "ozon", status: "delivered", quantity: 3)
    ledger_return(order, source_status: "ReceivedBySeller", quantity: 1)
    extra_skus = 11.times.map do |index|
      sku = Ec::Sku.create!(sku_code: "STOCK-#{index}-#{@token}", product_name: "Batch #{index}")
      product = Ec::SkuProduct.create!(
        sku_code: sku.sku_code, store: @ozon_store, product_id: "P-#{index}-#{@token}",
        platform_sku_id: "S-#{index}-#{@token}"
      )
      order.items.create!(
        platform: "ozon", store: @ozon_store, fulfillment: order.fulfillments.first,
        external_item_id: "I-#{index}-#{@token}", platform_sku_id: product.platform_sku_id, quantity: 2
      )
      sku
    end

    single, single_sql = measured_stock([ @sku.sku_code ])
    batch, batch_sql = measured_stock([ @sku.sku_code ] + extra_skus.map(&:sku_code))

    assert_equal single.fetch(@sku.sku_code), batch.fetch(@sku.sku_code)
    extra_skus.each { |sku| assert_equal(-2, batch.dig(sku.sku_code, :summary, :book_stock)) }
    assert_equal single_sql.size, batch_sql.size
    assert_operator batch_sql.size, :<=, 12
    assert_empty batch_sql.grep(/raw_ozon_supply|raw_wb_supply|raw_ozon_removal/)
  ensure
    product_ids = Ec::SkuProduct.where(sku_code: extra_skus&.map(&:sku_code)).pluck(:id)
    Ec::SkuProduct.where(sku_code: extra_skus&.map(&:sku_code)).delete_all
    Ec::Sku.with_deleted.where(id: extra_skus&.map(&:id)).delete_all
    Ec::OperationLog.where(record_type: "Ec::Sku", record_id: extra_skus&.map(&:id)).delete_all
    Ec::OperationLog.where(record_type: "Ec::SkuProduct", record_id: product_ids).delete_all
  end

  test "empty inputs issue no queries" do
    result, sql = measured_stock([])

    assert_empty result
    assert_empty sql
  end

  private

  def platform_level(platform, fulfillment_type, quantity, latest: true)
    store = platform == "wb" ? @wb_store : @ozon_store
    Ec::SkuInventoryLevel.create!(
      sku_code: @sku.sku_code, platform: platform, account_id: platform == "wb" ? @wb_account.id : @ozon_account.id,
      store: store, store_name: store.store_name, fulfillment_type: fulfillment_type,
      quantity: quantity, is_latest: latest, synced_at: Time.current
    )
  end

  def measured_stock(sku_codes)
    sql = []
    subscriber = ->(*, payload) { sql << payload[:sql] unless payload[:cached] || payload[:name] == "SCHEMA" }
    result = nil
    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      ActiveRecord::Base.uncached { result = Ec::InventoryPageStockQuery.new(sku_codes: sku_codes).call }
    end
    [ result, sql ]
  end
end
