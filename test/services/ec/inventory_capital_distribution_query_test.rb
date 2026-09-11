require "test_helper"

class Ec::InventoryCapitalDistributionQueryTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(5).upcase
    @sku = Ec::Sku.create!(
      sku_code: "CAPITAL-#{@token}",
      product_name: "资金分布测试商品"
    )
    @account = RawOzon::SellerAccount.create!(
      company_name: "资金分布 Ozon #{@token}",
      client_id: "capital-#{@token}",
      api_key: "key",
      company_type: "small"
    )
    @store = Ec::Store.create!(
      platform: "ozon",
      store_name: "资金分布店铺 #{@token}",
      company_type: "small",
      ozon_raw_account_id: @account.id
    )
    @sku_product = Ec::SkuProduct.create!(
      sku: @sku,
      store: @store,
      product_id: "PRODUCT-#{@token}",
      platform_sku_id: "PLATFORM-#{@token}"
    )
  end

  teardown do
    return_ids = Ec::Return.where(store_id: @store&.id).pluck(:id)
    Ec::ReturnItem.where(return_id: return_ids).delete_all
    Ec::Return.where(id: return_ids).delete_all
    order_ids = Ec::Order.where(store_id: @store&.id).pluck(:id)
    Ec::OrderItem.where(order_id: order_ids).delete_all
    Ec::Order.where(id: order_ids).delete_all
    RawOzon::RemovalItem.where(account_id: @account&.id).delete_all
    Ec::OperationLog.where(record_type: "Ec::SkuBatch", record_id: Ec::SkuBatch.where(sku_code: @sku&.sku_code).pluck(:id)).delete_all
    Ec::OperationLog.where(record_type: "Ec::SkuCost", record_id: Ec::SkuCost.where(sku_code: @sku&.sku_code).pluck(:id)).delete_all
    Ec::SkuBatch.where(sku_code: @sku&.sku_code).delete_all
    Ec::SkuCost.where(sku_code: @sku&.sku_code).delete_all
    Ec::SkuProduct.where(id: @sku_product&.id).delete_all
    Ec::Store.where(id: @store&.id).delete_all
    @account&.destroy
    Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
  end

  test "allocates sold quantities FIFO and prices each batch with the effective SKU cost" do
    Ec::SkuCost.create!(
      sku_code: @sku.sku_code,
      effective_on: Date.new(2026, 1, 1),
      purchase_price_cny: 10,
      freight_to_by_cny: 2,
      customs_misc_cny: 1,
      customs_duty_rate: 0,
      import_vat_rate: 0
    )
    Ec::SkuCost.create!(
      sku_code: @sku.sku_code,
      effective_on: Date.new(2026, 1, 2),
      purchase_price_cny: 20,
      freight_to_by_cny: 0,
      customs_misc_cny: 0,
      customs_duty_rate: 0,
      import_vat_rate: 0
    )

    first_batch = Ec::SkuBatch.create!(
      sku_code: @sku.sku_code,
      batch_code: "CAPITAL-A-#{@token}",
      batch_type: :normal,
      status: :received,
      purchased_quantity: 3,
      received_quantity: 3,
      purchase_date: Date.new(2026, 1, 1),
      received_on: Date.new(2026, 1, 3),
      purchase_unit_price_cny: 999
    )
    second_batch = Ec::SkuBatch.create!(
      sku_code: @sku.sku_code,
      batch_code: "CAPITAL-B-#{@token}",
      batch_type: :normal,
      status: :received,
      purchased_quantity: 5,
      received_quantity: 5,
      purchase_date: Date.new(2026, 1, 2),
      received_on: Date.new(2026, 1, 4),
      purchase_unit_price_cny: 1
    )
    incoming_batch = Ec::SkuBatch.create!(
      sku_code: @sku.sku_code,
      batch_code: "CAPITAL-C-#{@token}",
      batch_type: :normal,
      status: :in_transit,
      purchased_quantity: 4,
      received_quantity: 0,
      purchase_date: Date.new(2026, 1, 5),
      purchase_unit_price_cny: 500
    )

    order = Ec::Order.create!(
      platform: "ozon",
      store: @store,
      order_key: "capital-order-#{@token}",
      order_status: "delivered",
      ordered_at: Time.zone.parse("2026-01-10 10:00:00")
    )
    Ec::OrderItem.create!(
      order: order,
      store: @store,
      platform: "ozon",
      platform_sku_id: @sku_product.platform_sku_id,
      quantity: 5
    )

    result = Ec::InventoryCapitalDistributionQuery.new(skus: [@sku]).call
    rows = result.fetch(:batch_rows).index_by { |row| row[:batch_code] }

    assert_equal 3, rows.fetch(first_batch.batch_code)[:sold_quantity]
    assert_equal 0, rows.fetch(first_batch.batch_code)[:book_stock_quantity]
    assert_equal BigDecimal("13.0"), rows.fetch(first_batch.batch_code)[:unit_goods_cost_cny]
    assert_equal BigDecimal("39.0"), rows.fetch(first_batch.batch_code)[:sold_amount_cny]

    assert_equal 2, rows.fetch(second_batch.batch_code)[:sold_quantity]
    assert_equal 3, rows.fetch(second_batch.batch_code)[:book_stock_quantity]
    assert_equal BigDecimal("20.0"), rows.fetch(second_batch.batch_code)[:unit_goods_cost_cny]
    assert_equal BigDecimal("40.0"), rows.fetch(second_batch.batch_code)[:sold_amount_cny]

    assert_equal 4, rows.fetch(incoming_batch.batch_code)[:in_transit_quantity]
    assert_equal BigDecimal("80.0"), rows.fetch(incoming_batch.batch_code)[:in_transit_amount_cny]

    sku_row = result.fetch(:sku_rows).fetch(0)
    summary = result.fetch(:summary)
    assert_equal sku_row.slice(:in_transit_quantity, :book_stock_quantity, :sold_quantity, :total_quantity),
      summary.slice(:in_transit_quantity, :book_stock_quantity, :sold_quantity, :total_quantity)
    assert_equal 4, summary[:in_transit_quantity]
    assert_equal 3, summary[:book_stock_quantity]
    assert_equal 5, summary[:sold_quantity]
    assert_equal BigDecimal("219.0"), summary[:total_amount_cny]
    assert_equal 0, summary[:missing_cost_quantity]
  end

  test "uses restockable returns and Ozon removals when calculating sold quantity" do
    Ec::SkuCost.create!(
      sku_code: @sku.sku_code,
      effective_on: Date.new(2026, 1, 1),
      purchase_price_cny: 10,
      freight_to_by_cny: 0,
      customs_misc_cny: 0,
      customs_duty_rate: 0,
      import_vat_rate: 0
    )
    batch = Ec::SkuBatch.create!(
      sku_code: @sku.sku_code,
      batch_code: "CAPITAL-RET-#{@token}",
      batch_type: :normal,
      status: :received,
      purchased_quantity: 5,
      received_quantity: 5,
      purchase_date: Date.new(2026, 1, 1),
      received_on: Date.new(2026, 1, 2),
      purchase_unit_price_cny: 99
    )
    order = Ec::Order.create!(
      platform: "ozon",
      store: @store,
      order_key: "capital-return-order-#{@token}",
      order_status: "delivered",
      ordered_at: Time.zone.parse("2026-01-10 10:00:00")
    )
    order_item = Ec::OrderItem.create!(
      order: order,
      store: @store,
      platform: "ozon",
      platform_sku_id: @sku_product.platform_sku_id,
      quantity: 6
    )
    ec_return = Ec::Return.create!(
      platform: "ozon",
      store: @store,
      order: order,
      return_key: "capital-return-#{@token}",
      return_type: "customer_return",
      process_status: "completed"
    )
    Ec::ReturnItem.create!(
      return: ec_return,
      order_item: order_item,
      sku_product: @sku_product,
      store: @store,
      platform: "ozon",
      item_key: "capital-return-item-#{@token}",
      quantity: 2,
      restockable: true
    )
    RawOzon::RemovalItem.create!(
      account: @account,
      source_type: "stock",
      row_key: "capital-removal-#{@token}",
      return_id: "capital-removal-#{@token}",
      sku: @sku_product.platform_sku_id,
      quantity: 1,
      return_state: "В пути",
      raw_json: {},
      synced_at: Time.current
    )

    result = Ec::InventoryCapitalDistributionQuery.new(skus: [@sku]).call
    row = result.fetch(:batch_rows).find { |item| item[:batch_code] == batch.batch_code }

    assert_equal 5, row[:sold_quantity]
    assert_equal 0, row[:book_stock_quantity]
    assert_equal BigDecimal("50.0"), row[:sold_amount_cny]
    assert_nil result.fetch(:batch_rows).find { |item| item[:row_type] == "unmatched_sold" }
  end

  test "sorts SKU rows by sold quantity descending" do
    less_sold_sku = @sku
    more_sold_sku = Ec::Sku.create!(
      sku_code: "CAPITAL-MORE-#{@token}",
      product_name: "资金分布高销量商品"
    )
    more_sold_product = Ec::SkuProduct.create!(
      sku: more_sold_sku,
      store: @store,
      product_id: "PRODUCT-MORE-#{@token}",
      platform_sku_id: "PLATFORM-MORE-#{@token}"
    )

    [[less_sold_sku, "LESS"], [more_sold_sku, "MORE"]].each do |sku, suffix|
      Ec::SkuCost.create!(
        sku_code: sku.sku_code,
        effective_on: Date.new(2026, 1, 1),
        purchase_price_cny: 1,
        freight_to_by_cny: 0,
        customs_misc_cny: 0,
        customs_duty_rate: 0,
        import_vat_rate: 0
      )
      Ec::SkuBatch.create!(
        sku_code: sku.sku_code,
        batch_code: "CAPITAL-SORT-#{suffix}-#{@token}",
        batch_type: :normal,
        status: :received,
        purchased_quantity: 20,
        received_quantity: 20,
        purchase_date: Date.new(2026, 1, 1),
        received_on: Date.new(2026, 1, 2),
        purchase_unit_price_cny: 1
      )
    end

    create_order_for(@sku_product, quantity: 2, key_suffix: "less")
    create_order_for(more_sold_product, quantity: 7, key_suffix: "more")

    result = Ec::InventoryCapitalDistributionQuery.new(skus: [less_sold_sku, more_sold_sku]).call

    assert_equal [more_sold_sku.sku_code, less_sold_sku.sku_code], result.fetch(:sku_rows).map { |row| row[:sku_code] }
  ensure
    if defined?(more_sold_sku) && more_sold_sku
      Ec::OperationLog.where(record_type: "Ec::SkuBatch", record_id: Ec::SkuBatch.where(sku_code: more_sold_sku.sku_code).pluck(:id)).delete_all
      Ec::OperationLog.where(record_type: "Ec::SkuCost", record_id: Ec::SkuCost.where(sku_code: more_sold_sku.sku_code).pluck(:id)).delete_all
      Ec::SkuBatch.where(sku_code: more_sold_sku.sku_code).delete_all
      Ec::SkuCost.where(sku_code: more_sold_sku.sku_code).delete_all
      Ec::SkuProduct.where(sku_code: more_sold_sku.sku_code).delete_all
      Ec::Sku.with_deleted.where(id: more_sold_sku.id).delete_all
    end
  end

  private

  def create_order_for(sku_product, quantity:, key_suffix:)
    order = Ec::Order.create!(
      platform: "ozon",
      store: @store,
      order_key: "capital-#{key_suffix}-order-#{@token}",
      order_status: "delivered",
      ordered_at: Time.zone.parse("2026-01-10 10:00:00")
    )
    Ec::OrderItem.create!(
      order: order,
      store: @store,
      platform: "ozon",
      platform_sku_id: sku_product.platform_sku_id,
      quantity: quantity
    )
  end
end
