require "test_helper"

class Ec::SkuActualSellingPriceQueryTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(5).upcase
    @time_zone = ActiveSupport::TimeZone["Asia/Shanghai"]
    @sku = Ec::Sku.create!(sku_code: "ACT-PRICE-#{@token}")
    @other_sku = Ec::Sku.create!(sku_code: "ACT-PRICE-OTHER-#{@token}")
    @stores = %w[wb ozon].to_h do |platform|
      [platform, Ec::Store.create!(
        platform: platform,
        store_name: "Actual price #{platform} #{@token}",
        company_type: "general"
      )]
    end
    @products = [
      Ec::SkuProduct.create!(
        sku: @sku, store: @stores.fetch("wb"),
        product_id: "71001#{@token.hex % 1_000}", platform_sku_id: "WB-IGNORED-#{@token}"
      ),
      Ec::SkuProduct.create!(
        sku: @sku, store: @stores.fetch("ozon"),
        product_id: "OZON-#{@token}", platform_sku_id: "81001#{@token.hex % 1_000}"
      ),
      Ec::SkuProduct.create!(
        sku: @other_sku, store: @stores.fetch("wb"),
        product_id: "72001#{@token.hex % 1_000}", platform_sku_id: "OTHER-WB-#{@token}"
      )
    ]
    @orders = []
    @rate_dates = []
  end

  teardown do
    Ec::OrderItem.where(order_id: @orders.map(&:id)).delete_all
    Ec::Order.where(id: @orders.map(&:id)).delete_all
    Ec::DailyExchangeRate.where(rate_date: @rate_dates.uniq, source: "actual-price-test-#{@token.downcase}").delete_all
    Ec::OperationLog.where(record_type: "Ec::SkuProduct", record_id: @products.map(&:id)).delete_all
    Ec::OperationLog.where(record_type: "Ec::Store", record_id: @stores.values.map(&:id)).delete_all
    Ec::OperationLog.where(record_type: "Ec::Sku", record_id: [@sku.id, @other_sku.id]).delete_all
    Ec::SkuProduct.where(id: @products.map(&:id)).delete_all
    Ec::Store.where(id: @stores.values.map(&:id)).delete_all
    Ec::Sku.with_deleted.where(id: [@sku.id, @other_sku.id]).delete_all
  end

  test "calculates a quantity-weighted RUB average and excludes cancelled or unbound items" do
    create_item("wb", price: 100, quantity: 2, date: Date.new(2093, 8, 25), status: "delivered")
    create_item("wb", price: 200, quantity: 1, date: Date.new(2093, 9, 1), status: "returned")
    create_item("wb", price: 999, quantity: 5, date: Date.new(2093, 9, 2), status: "cancelled")
    create_item("wb", price: 888, quantity: 3, date: Date.new(2093, 9, 3), status: "delivered", product: @products.fetch(2))
    create_item("wb", price: 777, quantity: 1, date: Date.new(2093, 8, 23), status: "delivered")
    create_item("wb", price: 50, quantity: 1, date: Date.new(2093, 9, 4), status: "delivered", currency: "BYN")

    payload = query(platform: "wb", market: "ru")

    assert_equal Date.new(2093, 8, 24), payload.dig(:period, :from_date)
    assert_equal Date.new(2093, 9, 20), payload.dig(:period, :to_date)
    assert_equal Date.new(2093, 9, 1), payload.dig(:period, :data_through)
    assert_equal "RUB", payload.dig(:price, :source_currency)
    assert_equal 133.33.to_d, payload.dig(:price, :average_source)
    assert_equal 133.33.to_d, payload.dig(:price, :average_rub)
    assert_equal 2, payload.dig(:price, :item_count)
    assert_equal 3, payload.dig(:price, :unit_count)
  end

  test "uses BYN for Ozon Belarus and converts each order date to RUB before weighting" do
    first_date = Date.new(2093, 8, 25)
    second_date = Date.new(2093, 9, 1)
    create_daily_rates(first_date, byn_to_cny: 2, rub_to_cny: 0.1)
    create_daily_rates(second_date, byn_to_cny: 2.4, rub_to_cny: 0.08)
    create_item("ozon", price: 300, quantity: 2, date: first_date, status: "delivered", currency: "BYN")
    create_item("ozon", price: 400, quantity: 1, date: second_date, status: "shipped", currency: "BYN")
    create_item("ozon", price: 10_000, quantity: 1, date: second_date, status: "delivered", currency: "RUB")

    payload = query(platform: "ozon", market: "by")

    assert_equal "BYN", payload.dig(:price, :source_currency)
    assert_equal 333.33.to_d, payload.dig(:price, :average_source)
    assert_equal 8_000.to_d, payload.dig(:price, :average_rub)
    assert_equal 2, payload.dig(:price, :item_count)
    assert_equal 3, payload.dig(:price, :unit_count)
    assert_equal 0, payload.dig(:price, :missing_exchange_rate_item_count)
  end

  test "does not return a RUB result when the Ozon Belarus order-date rate is missing" do
    create_item("ozon", price: 300, quantity: 1, date: Date.new(2093, 9, 1), status: "delivered", currency: "BYN")

    payload = query(platform: "ozon", market: "by")

    assert_equal 300.to_d, payload.dig(:price, :average_source)
    assert_nil payload.dig(:price, :average_rub)
    assert_equal 1, payload.dig(:price, :item_count)
    assert_equal 1, payload.dig(:price, :missing_exchange_rate_item_count)
  end

  private

  def query(platform:, market:)
    Ec::SkuActualSellingPriceQuery.run(
      sku: @sku,
      platform: platform,
      market: market,
      today: Date.new(2093, 9, 21),
      time_zone: @time_zone
    )
  end

  def create_item(platform, price:, quantity:, date:, status:, currency: "RUB", product: nil)
    product ||= platform == "wb" ? @products.fetch(0) : @products.fetch(1)
    store = @stores.fetch(platform)
    order = Ec::Order.create!(
      platform: platform,
      store: store,
      order_key: "ACT-PRICE-#{@token}-#{@orders.size}",
      order_status: status,
      ordered_at: @time_zone.local(date.year, date.month, date.day, 12)
    )
    @orders << order
    order.items.create!(
      platform: platform,
      store: store,
      platform_sku_id: platform == "wb" ? product.product_id : product.platform_sku_id,
      quantity: quantity,
      buyer_paid_unit_price: price,
      buyer_currency_code: currency
    )
  end

  def create_daily_rates(date, byn_to_cny:, rub_to_cny:)
    @rate_dates << date
    { "BYN" => byn_to_cny, "RUB" => rub_to_cny }.each do |currency, rate|
      Ec::DailyExchangeRate.create!(
        rate_date: date,
        base_currency: "CNY",
        currency_code: currency,
        rate_to_base: rate,
        rate_from_base: 1.to_d / rate,
        source: "actual-price-test-#{@token.downcase}",
        source_date: date
      )
    end
  end
end
