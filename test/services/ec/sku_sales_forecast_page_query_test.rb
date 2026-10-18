require "test_helper"

class Ec::SkuSalesForecastPageQueryTest < ActiveSupport::TestCase
  setup do
    @sku = Ec::Sku.create!(sku_code: "FORECAST-PAGE-#{SecureRandom.hex(4).upcase}", product_name: "Forecast page")
    @from_date = Date.new(2026, 8, 1)
    @to_date = @from_date + 55.days
    @price_date = Date.new(2094, 8, 1)
    @rate_source = "forecast-page-test-#{@sku.id}"
    @store = Ec::Store.create!(platform: "wb", store_name: "Forecast page store", company_type: "small")
    Ec::SkuProduct.create!(sku_code: @sku.sku_code, store: @store, platform: "wb", product_id: "12345")
    order = Ec::Order.create!(
      platform: "wb", store: @store, order_key: "forecast-page-#{@sku.id}",
      external_order_id: "forecast-page-#{@sku.id}", order_status: "delivered",
      ordered_at: @from_date.in_time_zone("Asia/Shanghai").noon
    )
    order.items.create!(
      platform: "wb", store: @store, platform_sku_id: "12345", quantity: 2,
      unit_price: 100, buyer_paid_unit_price: 90, currency_code: "RUB",
      buyer_currency_code: "RUB", external_item_id: "forecast-page-item-#{@sku.id}"
    )
    recent_order = Ec::Order.create!(
      platform: "wb", store: @store, order_key: "forecast-page-recent-#{@sku.id}",
      external_order_id: "forecast-page-recent-#{@sku.id}", order_status: "delivered",
      ordered_at: (@from_date + 40.days).in_time_zone("Asia/Shanghai").noon
    )
    recent_order.items.create!(
      platform: "wb", store: @store, platform_sku_id: "12345", quantity: 30,
      unit_price: 100, buyer_paid_unit_price: 90, currency_code: "RUB",
      buyer_currency_code: "RUB", external_item_id: "forecast-page-recent-item-#{@sku.id}"
    )
    Ec::Snapshot.insert_all!(56.times.map do |index|
      {
        snapshot_type: Ec::InventorySnapshot.snapshot_type,
        snapshot_date: @from_date + index.days,
        sku_id: @sku.id,
        content: {
          overview: {
            daily_sales: index < 14 ? 2 : 4,
            daily_sales_velocity: 3,
            platform_stock: index.zero? ? 0 : 20,
            book_stock: 30,
            out_of_stock: index.zero?
          }
        }
      }
    end)
  end

  teardown do
    Ec::DailyExchangeRate.where(source: @rate_source).delete_all
    Ec::OrderItem.where(store_id: @store&.id).delete_all if @store
    Ec::Order.where(store_id: @store&.id).delete_all if @store
    Ec::Snapshot.where(sku_id: @sku&.id).delete_all if @sku
    Ec::SkuProduct.where(sku_code: @sku&.sku_code).delete_all if @sku
    Ec::Store.where(id: @store.id).delete_all if @store
    Ec::Sku.with_deleted.where(id: @sku.id).delete_all if @sku
  end

  test "combines four forecast values with historical facts and backtests" do
    result = described_class.new(
      sku: @sku,
      as_of_date: @from_date + 40.days
    ).call

    assert_equal @from_date - 15.days, result.dig(:period, :from)
    assert_equal @from_date + 47.days, result.dig(:period, :to)
    assert_equal 63, result.fetch(:timeline).size
    assert_equal BigDecimal("2.9429"), result.dig(:forecasts, :simple, :daily_sales)
    assert_equal BigDecimal("3.9111"), result.dig(:forecasts, :strict, :daily_sales)
    first_snapshot = result.fetch(:timeline).find { |row| row[:date] == @from_date }
    assert_equal BigDecimal("2"), first_snapshot[:actual_sales]
    assert first_snapshot[:out_of_stock]
    assert_equal BigDecimal("90"), first_snapshot[:price]
    assert result.fetch(:backtests).any?
    assert result.dig(:forecasts, :version_1, :daily_sales).present?
    assert result.dig(:forecasts, :version_2, :daily_sales).present?
    assert_equal 28, result.dig(:forecasts, :version_1, :training_days)
    assert_equal 28, result.dig(:forecasts, :version_1, :inventory_days)
    assert_equal 28, result.dig(:forecasts, :version_2, :training_days)
    assert_equal 28, result.dig(:forecasts, :version_2, :inventory_days)
    assert_equal @from_date + 13.days, result.dig(:forecasts, :version_1, :calculation, :from)
    assert_equal @from_date + 40.days, result.dig(:forecasts, :version_2, :calculation, :to)
    assert result[:backtests].all? { |row| row[:target_to] <= result.dig(:period, :as_of) }
  end

  test "moves the entire history window with the forecast cutoff" do
    [ @from_date + 20.days, @to_date ].each do |as_of|
      result = described_class.new(sku: @sku, as_of_date: as_of).call

      assert_equal as_of - 55.days, result.dig(:period, :from)
      assert_equal as_of + 7.days, result.dig(:period, :to)
      assert_equal (as_of - 55.days..as_of + 7.days).to_a, result[:timeline].map { |row| row[:date] }
      %i[version_1 version_2].each do |version|
        calculation = result.dig(:forecasts, version, :calculation)
        assert_equal as_of - 27.days, calculation[:from]
        assert_equal as_of, calculation[:to]
      end
    end
  end

  test "caps followup history at today without changing forecasts or backtests" do
    as_of = @to_date - 5.days
    cutoff_report = travel_to(as_of.in_time_zone("Asia/Shanghai").noon) do
      described_class.new(sku: @sku, as_of_date: as_of).call
    end
    today = as_of + 3.days
    expanded_report = travel_to(today.in_time_zone("Asia/Shanghai").noon) do
      described_class.new(sku: @sku, as_of_date: as_of).call
    end

    assert_equal as_of, cutoff_report.dig(:period, :to)
    assert_equal 56, cutoff_report[:timeline].size
    assert_equal today, expanded_report.dig(:period, :to)
    assert_equal 59, expanded_report[:timeline].size
    assert_equal today, expanded_report[:timeline].last[:date]
    assert_equal BigDecimal("4"), expanded_report[:timeline].last[:actual_sales]
    assert_equal BigDecimal("20"), expanded_report[:timeline].last[:inventory]
    assert_equal cutoff_report[:timeline], expanded_report[:timeline].first(56)
    assert_equal cutoff_report[:forecasts], expanded_report[:forecasts]
    assert_equal cutoff_report[:backtests], expanded_report[:backtests]
  end

  test "caps followup history using the requested time zone" do
    travel_to Time.utc(2026, 8, 25, 20) do
      result = described_class.new(sku: @sku, as_of_date: Date.new(2026, 8, 24), time_zone: "UTC").call

      assert_equal Date.new(2026, 8, 25), result.dig(:period, :to)
      assert_equal Date.new(2026, 8, 25), result[:timeline].last[:date]
    end
  end

  test "converts matching price currencies to RUB before quantity weighting" do
    create_rates(@price_date, "RUB" => "0.1", "BYN" => "2", "USD" => "7")
    create_price_item(date: @price_date, quantity: 2, buyer_paid_unit_price: 90, buyer_currency_code: "RUB")
    create_price_item(date: @price_date, quantity: 3, buyer_paid_unit_price: 10, buyer_currency_code: "BYN")
    create_price_item(date: @price_date, quantity: 1, buyer_paid_unit_price: 5, buyer_currency_code: "USD")
    create_price_item(date: @price_date, quantity: 1, buyer_paid_unit_price: nil, buyer_currency_code: "BYN", unit_price: 5, currency_code: "CNY")
    %w[cancelled returned].each do |status|
      create_price_item(date: @price_date, status: status, buyer_paid_unit_price: 99_999, buyer_currency_code: "UNKNOWN")
    end

    report = price_report

    assert_equal "RUB", report[:price_currency]
    assert_equal BigDecimal("168.5714"), report[:timeline].find { |row| row[:date] == @price_date }[:price]
  end

  test "uses each order dates rate and computes chronological price changes" do
    create_rates(@price_date, "RUB" => "0.1", "BYN" => "2")
    create_rates(@price_date + 1.day, "RUB" => "0.08", "BYN" => "2.4")
    [@price_date, @price_date + 1.day].each do |date|
      create_price_item(date: date, buyer_paid_unit_price: 10, buyer_currency_code: "BYN")
    end

    rows = price_report[:timeline].index_by { |row| row[:date] }

    assert_equal 200.to_d, rows[@price_date][:price]
    assert_nil rows[@price_date][:price_change]
    assert_equal 300.to_d, rows[@price_date + 1.day][:price]
    assert_equal 100.to_d, rows[@price_date + 1.day][:price_change]
  end

  test "keeps the daily average unavailable when any currency or required rate is missing" do
    create_rates(@price_date, "RUB" => "0.1")
    create_rates(@price_date + 1.day, "BYN" => "2")
    3.times do |index|
      date = @price_date + index.days
      create_price_item(date: date, buyer_paid_unit_price: 90, buyer_currency_code: "RUB")
      create_price_item(date: date, buyer_paid_unit_price: 10, buyer_currency_code: index == 2 ? nil : "BYN")
    end
    create_price_item(date: @price_date + 3.days, buyer_paid_unit_price: 90, buyer_currency_code: "RUB")

    rows = price_report[:timeline].index_by { |row| row[:date] }

    3.times { |index| assert_nil rows[@price_date + index.days][:price] }
    assert_equal 90.to_d, rows[@price_date + 3.days][:price]
  end

  test "selects exchange rates using the orders date in the requested time zone" do
    create_rates(@price_date - 1.day, "RUB" => "0.1", "BYN" => "1")
    create_rates(@price_date, "RUB" => "0.1", "BYN" => "2")
    create_price_item(
      date: @price_date, ordered_at: Time.utc(2094, 7, 31, 20),
      buyer_paid_unit_price: 10, buyer_currency_code: "BYN"
    )

    shanghai = price_report[:timeline].index_by { |row| row[:date] }
    utc = price_report(time_zone: "UTC")[:timeline].index_by { |row| row[:date] }

    assert_equal 200.to_d, shanghai[@price_date][:price]
    assert_nil shanghai[@price_date - 1.day][:price]
    assert_equal 100.to_d, utc[@price_date - 1.day][:price]
    assert_nil utc[@price_date][:price]
  end

  private

  def create_price_item(date:, status: "delivered", ordered_at: nil, **attributes)
    order = Ec::Order.create!(
      platform: "wb", store: @store, order_key: "forecast-price-#{SecureRandom.hex(8)}",
      order_status: status, ordered_at: ordered_at || date.in_time_zone("Asia/Shanghai").noon
    )
    order.items.create!(**{
      platform: "wb", store: @store, platform_sku_id: "12345", quantity: 1,
      unit_price: 100, currency_code: "RUB"
    }.merge(attributes))
  end

  def create_rates(date, rates)
    rates.each do |currency, rate|
      Ec::DailyExchangeRate.create!(
        rate_date: date, base_currency: "CNY", currency_code: currency,
        rate_to_base: rate.to_d, rate_from_base: 1.to_d / rate.to_d,
        source: @rate_source
      )
    end
  end

  def price_report(time_zone: "Asia/Shanghai")
    travel_to((@price_date + 7.days).in_time_zone(time_zone).noon) do
      described_class.new(sku: @sku, as_of_date: @price_date, time_zone: time_zone).call
    end
  end

  def described_class
    Ec::SkuSalesForecastPageQuery
  end
end
