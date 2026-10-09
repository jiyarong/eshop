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

  test "returns quantity-weighted WB commission base and buyer paid averages, excluding cancelled and unbound items" do
    create_item("wb", commission_base: 150, buyer_paid: 100, quantity: 2, date: Date.new(2093, 8, 25), status: "delivered")
    create_item("wb", commission_base: 300, buyer_paid: 200, quantity: 1, date: Date.new(2093, 9, 1), status: "returned")
    create_item("wb", commission_base: 999, buyer_paid: 999, quantity: 5, date: Date.new(2093, 9, 2), status: "cancelled")
    create_item("wb", commission_base: 888, buyer_paid: 888, quantity: 3, date: Date.new(2093, 9, 3), status: "delivered", product: @products.fetch(2))
    create_item("wb", commission_base: 777, buyer_paid: 777, quantity: 1, date: Date.new(2093, 8, 23), status: "delivered")

    payload = query(platform: "wb", market: "ru")

    assert_equal Date.new(2093, 8, 24), payload.dig(:period, :from_date)
    assert_equal Date.new(2093, 9, 20), payload.dig(:period, :to_date)
    assert_equal Date.new(2093, 9, 1), payload.dig(:period, :data_through)
    assert_equal "RUB", payload.dig(:commission_base_price, :source_currency)
    assert_equal 200.to_d, payload.dig(:commission_base_price, :average_rub)
    assert_equal 133.33.to_d, payload.dig(:buyer_paid_price, :average_rub)
    assert_equal 2, payload.dig(:commission_base_price, :item_count)
    assert_equal 3, payload.dig(:commission_base_price, :unit_count)
    assert_not payload.key?(:price)
    assert_not payload.key?(:seller_price)
  end

  test "commission base price does not depend on a buyer paid price being present" do
    create_item("wb", commission_base: 1450, buyer_paid: nil, quantity: 1, date: Date.new(2093, 9, 1), status: "shipped")

    payload = query(platform: "wb", market: "ru")

    assert_equal 1450.to_d, payload.dig(:commission_base_price, :average_rub)
    assert_equal 1, payload.dig(:commission_base_price, :item_count)
    assert_equal 0, payload.dig(:buyer_paid_price, :item_count)
    assert_nil payload.dig(:buyer_paid_price, :average_rub)
  end

  test "ignores zero prices" do
    create_item("wb", commission_base: 0, buyer_paid: 0, quantity: 1, date: Date.new(2093, 9, 1), status: "delivered")

    payload = query(platform: "wb", market: "ru")

    assert_equal 0, payload.dig(:commission_base_price, :item_count)
    assert_equal 0, payload.dig(:buyer_paid_price, :item_count)
  end

  test "uses BYN buyers for Ozon Belarus and converts each order date to RUB before weighting" do
    first_date = Date.new(2093, 8, 25)
    second_date = Date.new(2093, 9, 1)
    create_daily_rates(first_date, byn_to_cny: 2, rub_to_cny: 0.1)
    create_daily_rates(second_date, byn_to_cny: 2.4, rub_to_cny: 0.08)
    create_item("ozon", commission_base: 25_000, buyer_paid: 300, quantity: 2, date: first_date, status: "delivered", buyer_currency: "BYN")
    create_item("ozon", commission_base: 30_000, buyer_paid: 400, quantity: 1, date: second_date, status: "shipped", buyer_currency: "BYN")
    create_item("ozon", commission_base: 10_000, buyer_paid: 9_000, quantity: 1, date: second_date, status: "delivered", buyer_currency: "RUB")

    payload = query(platform: "ozon", market: "by")

    assert_equal "BYN", payload.dig(:buyer_paid_price, :source_currency)
    assert_equal 333.33.to_d, payload.dig(:buyer_paid_price, :average_source)
    assert_equal 8_000.to_d, payload.dig(:buyer_paid_price, :average_rub)
    assert_equal 2, payload.dig(:buyer_paid_price, :item_count)
    assert_equal 0, payload.dig(:buyer_paid_price, :missing_exchange_rate_item_count)
    assert_equal "RUB", payload.dig(:commission_base_price, :source_currency)
    assert_equal 26_666.67.to_d, payload.dig(:commission_base_price, :average_rub)
    assert_equal 3, payload.dig(:commission_base_price, :unit_count)
  end

  test "converts an Ozon commission base priced in BYN to RUB by order date" do
    date = Date.new(2093, 9, 1)
    create_daily_rates(date, byn_to_cny: 2, rub_to_cny: 0.1)
    create_item("ozon", commission_base: 237, commission_currency: "BYN", buyer_paid: 7_504, quantity: 1, date: date, status: "delivered")

    payload = query(platform: "ozon", market: "ru")

    assert_equal "BYN", payload.dig(:commission_base_price, :source_currency)
    assert_equal 237.to_d, payload.dig(:commission_base_price, :average_source)
    assert_equal 4_740.to_d, payload.dig(:commission_base_price, :average_rub)
    assert_equal 7_504.to_d, payload.dig(:buyer_paid_price, :average_rub)
  end

  test "returns separate Ozon Russia commission base and buyer paid RUB averages" do
    first_date = Date.new(2093, 8, 25)
    second_date = Date.new(2093, 9, 1)
    create_item("ozon", commission_base: 27_000, buyer_paid: 15_000, quantity: 2, date: first_date, status: "delivered")
    create_item("ozon", commission_base: 30_000, buyer_paid: 18_000, quantity: 1, date: second_date, status: "shipped")

    payload = query(platform: "ozon", market: "ru")

    assert_equal 28_000.to_d, payload.dig(:commission_base_price, :average_rub)
    assert_equal 16_000.to_d, payload.dig(:buyer_paid_price, :average_rub)
    assert_equal 3, payload.dig(:commission_base_price, :unit_count)
    assert_equal 3, payload.dig(:buyer_paid_price, :unit_count)
  end

  test "Ozon items without a buyer currency cannot be assigned to a market" do
    create_item("ozon", commission_base: 27_000, buyer_paid: nil, quantity: 1, date: Date.new(2093, 9, 1), status: "delivered")

    assert_equal 0, query(platform: "ozon", market: "ru").dig(:commission_base_price, :item_count)
    assert_equal 0, query(platform: "ozon", market: "by").dig(:commission_base_price, :item_count)
  end

  test "does not return a RUB result when the Ozon Belarus order-date rate is missing" do
    create_item("ozon", commission_base: 100, buyer_paid: 300, quantity: 1, date: Date.new(2093, 9, 1), status: "delivered", buyer_currency: "BYN")

    payload = query(platform: "ozon", market: "by")

    assert_equal 300.to_d, payload.dig(:buyer_paid_price, :average_source)
    assert_nil payload.dig(:buyer_paid_price, :average_rub)
    assert_equal 1, payload.dig(:buyer_paid_price, :missing_exchange_rate_item_count)
    assert_equal 100.to_d, payload.dig(:commission_base_price, :average_rub)
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

  def create_item(platform, commission_base:, buyer_paid:, quantity:, date:, status:, buyer_currency: "RUB",
                  commission_currency: "RUB", product: nil)
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
      unit_price: commission_base,
      currency_code: commission_base && commission_currency,
      buyer_paid_unit_price: buyer_paid,
      buyer_currency_code: buyer_paid && buyer_currency
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
