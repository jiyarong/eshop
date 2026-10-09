require "test_helper"

class Ec::SkuOperationTrendQueryTest < ActiveSupport::TestCase
  test "smooths weekly unit profit across each day of the completed week" do
    sku = Struct.new(:sku_code).new("TREND-PROFIT")
    account = Struct.new(:name).new("Profit Shop")
    store = Struct.new(:id, :wb_raw_account_id, :raw_wb_account) do
      def wb? = true
      def platform = "wb"
    end.new(12, 34, account)
    calls = []
    runner = lambda do |from_date:, to_date:, sku_codes:|
      calls << { from_date: from_date, to_date: to_date, sku_codes: sku_codes }
      { rows: [{ sku: "TREND-PROFIT", platform: "WB", shop: "Profit Shop", net_sales: 4, after_tax: 100 }] }
    end
    query = Ec::SkuOperationTrendQuery.new(
      sku: sku,
      store: store,
      from_date: Date.new(2026, 8, 3),
      to_date: Date.new(2026, 8, 9),
      time_zone: ActiveSupport::TimeZone["Asia/Shanghai"],
      profit_query_runner: runner
    )

    rows = query.send(:daily_unit_profit_rows)

    assert_equal 7, rows.size
    assert_equal [25.0], rows.map { |row| row[:unit_profit] }.uniq
    assert_equal((Date.new(2026, 8, 3)..Date.new(2026, 8, 9)).to_a, rows.map { |row| row[:date] })
    assert_equal Date.new(2026, 8, 3), calls.first[:from_date]
    assert_equal Date.new(2026, 8, 9), calls.first[:to_date]
    assert_equal ["TREND-PROFIT"], calls.first[:sku_codes]
  end

  test "plots the commission base price per currency on the shared price axis" do
    query = Ec::SkuOperationTrendQuery.new(
      sku: Struct.new(:sku_code).new("TREND-BASE"),
      store: Struct.new(:platform).new("wb"),
      from_date: Date.new(2026, 8, 3),
      to_date: Date.new(2026, 8, 9),
      time_zone: ActiveSupport::TimeZone["Asia/Shanghai"]
    )
    rows = [{ date: Date.new(2026, 8, 3), currency: "RUB", price: BigDecimal("1450.05") }]

    option = query.send(:chart_option, [], rows, [], [], [])

    series = option[:series].find do |item|
      item[:name] == I18n.t("erp.operation_actions.trends.commission_base_price_currency", currency: "RUB")
    end
    assert_not_nil series
    assert_equal 0, series[:yAxisIndex]
    assert_equal [["2026-08-03", 1450.05]], series[:data]
    assert_equal 3, option[:yAxis].size
  end

  test "averages the commission base price per day and currency weighted by quantity" do
    token = SecureRandom.hex(4).upcase
    sku = Ec::Sku.create!(sku_code: "TREND-BASE-#{token}")
    store = Ec::Store.create!(platform: "wb", store_name: "Trend base #{token}", company_type: "general")
    product = Ec::SkuProduct.create!(sku: sku, store: store, product_id: "7100#{token.hex % 100_000}", platform_sku_id: "x-#{token}")
    zone = ActiveSupport::TimeZone["Asia/Shanghai"]
    orders = [[100, 1, "RUB"], [200, 2, "RUB"], [50, 1, "BYN"], [nil, 5, "RUB"]].each_with_index.map do |(price, quantity, currency), index|
      order = Ec::Order.create!(
        platform: "wb", store: store, order_key: "TREND-BASE-#{token}-#{index}", order_status: "delivered",
        ordered_at: zone.local(2026, 8, 4, 12)
      )
      order.items.create!(
        platform: "wb", store: store, platform_sku_id: product.product_id, quantity: quantity,
        unit_price: price, currency_code: currency
      )
      order
    end
    query = Ec::SkuOperationTrendQuery.new(
      sku: sku, store: store, from_date: Date.new(2026, 8, 3), to_date: Date.new(2026, 8, 9), time_zone: zone,
      profit_query_runner: ->(from_date:, to_date:, sku_codes:) { { rows: [] } }
    )

    rows = query.send(:commission_base_price_rows, [product])

    assert_equal [["RUB", BigDecimal("166.67")], ["BYN", BigDecimal("50")]].sort, rows.map { |row| [row[:currency], row[:price]] }.sort
    assert_equal true, query.call.fetch(:has_commission_base_price)
  ensure
    Ec::OrderItem.where(order_id: orders&.map(&:id)).delete_all
    Ec::Order.where(id: orders&.map(&:id)).delete_all
    Ec::OperationLog.where(record_type: %w[Ec::SkuProduct Ec::Store Ec::Sku]).where(record_id: [product&.id, store&.id, sku&.id].compact).delete_all
    product&.delete
    store&.delete
    Ec::Sku.with_deleted.where(id: sku&.id).delete_all if sku
  end

  test "hides net sales and unit profit series by default" do
    query = Ec::SkuOperationTrendQuery.new(
      sku: Struct.new(:sku_code).new("TREND-LEGEND"),
      store: Struct.new(:platform).new("wb"),
      from_date: Date.new(2026, 8, 3),
      to_date: Date.new(2026, 8, 9),
      time_zone: ActiveSupport::TimeZone["Asia/Shanghai"]
    )

    option = query.send(:chart_option, [], [], [], [], [])

    assert_equal false, option.dig(:legend, :selected, I18n.t("erp.operation_actions.trends.metrics.net_sales"))
    assert_equal false, option.dig(:legend, :selected, I18n.t("erp.operation_actions.trends.metrics.unit_profit"))
  end
end
