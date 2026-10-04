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

  test "allocates settled net sales FIFO and keeps financial results on the weekly profit basis" do
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
      customs_misc_cny: 2,
      customs_duty_rate: BigDecimal("0.1"),
      import_vat_rate: BigDecimal("0.2")
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

    result = Ec::InventoryCapitalDistributionQuery.new(
      skus: [@sku],
      profit_report: profit_report(@sku.sku_code, net_sales_quantity: 5, sales_revenue_cny: 600,
        sold_goods_cost_cny: 60, sold_customs_tax_cost_cny: 19, goods_cost_cny: 79, net_profit_cny: 120)
    ).call
    rows = result.fetch(:batch_rows).index_by { |row| row[:batch_code] }

    assert_equal 3, rows.fetch(first_batch.batch_code)[:sold_quantity]
    assert_equal 0, rows.fetch(first_batch.batch_code)[:book_stock_quantity]
    assert_equal BigDecimal("12.0"), rows.fetch(first_batch.batch_code)[:unit_goods_and_freight_cost_cny]
    assert_equal BigDecimal("1.0"), rows.fetch(first_batch.batch_code)[:unit_customs_tax_cost_cny]

    assert_equal 2, rows.fetch(second_batch.batch_code)[:sold_quantity]
    assert_equal 3, rows.fetch(second_batch.batch_code)[:book_stock_quantity]
    assert_equal BigDecimal("20.0"), rows.fetch(second_batch.batch_code)[:unit_goods_and_freight_cost_cny]
    assert_equal BigDecimal("8.4"), rows.fetch(second_batch.batch_code)[:unit_customs_tax_cost_cny]
    assert_equal BigDecimal("60.0"), rows.fetch(second_batch.batch_code)[:book_stock_goods_cost_cny]
    assert_equal BigDecimal("25.2"), rows.fetch(second_batch.batch_code)[:book_stock_customs_tax_cost_cny]
    assert_equal BigDecimal("85.2"), rows.fetch(second_batch.batch_code)[:book_stock_amount_cny]

    assert_equal 4, rows.fetch(incoming_batch.batch_code)[:in_transit_quantity]
    assert_equal BigDecimal("80.0"), rows.fetch(incoming_batch.batch_code)[:in_transit_amount_cny]
    assert_equal BigDecimal("80.0"), rows.fetch(incoming_batch.batch_code)[:in_transit_goods_cost_cny]

    sku_row = result.fetch(:sku_rows).fetch(0)
    summary = result.fetch(:summary)
    assert_equal sku_row.slice(:in_transit_quantity, :book_stock_quantity, :net_sales_quantity, :total_quantity),
      summary.slice(:in_transit_quantity, :book_stock_quantity, :net_sales_quantity, :total_quantity)
    assert_equal 4, summary[:in_transit_quantity]
    assert_equal 3, summary[:book_stock_quantity]
    assert_equal 5, summary[:net_sales_quantity]
    assert_equal BigDecimal("80.0"), summary[:in_transit_goods_cost_cny]
    assert_equal BigDecimal("60.0"), summary[:book_stock_goods_cost_cny]
    assert_equal BigDecimal("25.2"), summary[:book_stock_customs_tax_cost_cny]
    assert_equal BigDecimal("165.2"), summary[:total_amount_cny]
    assert_equal BigDecimal("600.0"), summary[:sales_revenue_cny]
    assert_equal BigDecimal("60.0"), summary[:sold_goods_cost_cny]
    assert_equal BigDecimal("19.0"), summary[:sold_customs_tax_cost_cny]
    assert_equal BigDecimal("79.0"), summary[:goods_cost_cny]
    assert_equal summary[:goods_cost_cny], summary[:sold_goods_cost_cny] + summary[:sold_customs_tax_cost_cny]
    assert_equal BigDecimal("120.0"), summary[:net_profit_cny]
    assert_equal BigDecimal("-8.25"), summary[:unallocated_total_cny]
    assert_equal 0, summary[:missing_cost_quantity]
    assert_equal 0, summary[:missing_freight_quantity]
  end

  test "uses settled net sales instead of ERP orders and returns" do
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
    RawOzon::RemovalItem.create!(
      account: @account,
      source_type: "stock",
      row_key: "capital-removal-received-#{@token}",
      return_id: "capital-removal-received-#{@token}",
      sku: @sku_product.platform_sku_id,
      quantity: 1,
      return_state: "Завершено",
      box_state: "Получена",
      raw_json: {},
      synced_at: Time.current
    )

    result = Ec::InventoryCapitalDistributionQuery.new(
      skus: [@sku],
      profit_report: profit_report(@sku.sku_code, net_sales_quantity: 4)
    ).call
    row = result.fetch(:batch_rows).find { |item| item[:batch_code] == batch.batch_code }

    assert_equal 4, row[:sold_quantity]
    assert_equal 1, row[:book_stock_quantity]
    assert_nil result.fetch(:batch_rows).find { |item| item[:row_type] == "unmatched_sold" }
  end

  test "flags cleared inventory whose effective cost has no freight" do
    Ec::SkuCost.create!(
      sku_code: @sku.sku_code,
      effective_on: Date.new(2026, 1, 1),
      purchase_price_cny: 10,
      freight_to_by_cny: nil,
      customs_misc_cny: 1,
      customs_duty_rate: 0,
      import_vat_rate: 0
    )
    batch = Ec::SkuBatch.create!(
      sku_code: @sku.sku_code,
      batch_code: "CAPITAL-NO-FREIGHT-#{@token}",
      batch_type: :normal,
      status: :closed,
      purchased_quantity: 4,
      received_quantity: 4,
      purchase_date: Date.new(2026, 1, 1),
      received_on: Date.new(2026, 1, 2),
      purchase_unit_price_cny: 10
    )

    result = Ec::InventoryCapitalDistributionQuery.new(
      skus: [ @sku ],
      profit_report: profit_report(@sku.sku_code, net_sales_quantity: 0)
    ).call
    row = result.fetch(:batch_rows).find { |item| item[:batch_code] == batch.batch_code }

    assert row[:missing_freight]
    assert_equal 4, result.dig(:summary, :missing_freight_quantity)
  end

  test "keeps settled sales without purchase batches as unmatched financial quantity" do
    result = Ec::InventoryCapitalDistributionQuery.new(
      skus: [ @sku ],
      profit_report: profit_report(@sku.sku_code, net_sales_quantity: 3, sales_revenue_cny: 90,
        goods_cost_cny: 30, net_profit_cny: 12)
    ).call

    unmatched_row = result.fetch(:batch_rows).sole
    sku_row = result.fetch(:sku_rows).sole

    assert_equal "unmatched_sold", unmatched_row[:row_type]
    assert_equal 3, unmatched_row[:sold_quantity]
    assert_equal 3, sku_row[:net_sales_quantity]
    assert_equal BigDecimal("90"), sku_row[:sales_revenue_cny]
    assert_equal 1, result.dig(:summary, :sku_count)
    assert_equal 0, result.dig(:summary, :batch_count)
  end

  test "sorts SKU rows by sold quantity descending" do
    less_sold_sku = @sku
    more_sold_sku = Ec::Sku.create!(
      sku_code: "CAPITAL-MORE-#{@token}",
      product_name: "资金分布高销量商品"
    )
    Ec::SkuProduct.create!(
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

    report = profit_report(less_sold_sku.sku_code, net_sales_quantity: 2)
    report[:rows_by_sku][more_sold_sku.sku_code] = profit_metrics(net_sales_quantity: 7)
    result = Ec::InventoryCapitalDistributionQuery.new(
      skus: [less_sold_sku, more_sold_sku],
      profit_report: report
    ).call

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

  def profit_report(sku_code, **metrics)
    {
      rows_by_sku: { sku_code => profit_metrics(**metrics) },
      period_from: Date.new(2026, 1, 5),
      period_to: Date.new(2026, 1, 11),
      cutoff_date: Date.new(2026, 1, 11),
      unallocated_total_cny: BigDecimal("-8.25"),
      missing_week_starts: []
    }
  end

  def profit_metrics(net_sales_quantity:, sales_revenue_cny: 0, sold_goods_cost_cny: nil,
    sold_customs_tax_cost_cny: 0, goods_cost_cny: 0, net_profit_cny: 0)
    sold_goods_cost_cny = goods_cost_cny if sold_goods_cost_cny.nil?
    {
      net_sales_quantity: net_sales_quantity,
      sales_revenue_cny: BigDecimal(sales_revenue_cny.to_s),
      sold_goods_cost_cny: BigDecimal(sold_goods_cost_cny.to_s),
      sold_customs_tax_cost_cny: BigDecimal(sold_customs_tax_cost_cny.to_s),
      goods_cost_cny: BigDecimal(goods_cost_cny.to_s),
      net_profit_cny: BigDecimal(net_profit_cny.to_s)
    }
  end
end
