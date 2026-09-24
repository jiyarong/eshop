require "test_helper"

class Ec::SkuActualLogisticsQueryTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(5).upcase
    @sku = Ec::Sku.create!(sku_code: "ACT-LOG-#{@token}")
    @accounts = 2.times.map do |index|
      RawOzon::SellerAccount.create!(
        client_id: "actual-logistics-#{index}-#{@token}",
        api_key: "key-#{@token}",
        company_name: "Actual logistics #{index}",
        company_type: "general"
      )
    end
    @stores = @accounts.each_with_index.map do |account, index|
      Ec::Store.create!(
        platform: "ozon",
        store_name: "Actual logistics #{index} #{@token}",
        company_type: "general",
        ozon_raw_account_id: account.id
      )
    end
    @platform_sku_ids = [rand(10_000_000..19_999_999), rand(20_000_000..29_999_999)]
    @products = @stores.each_with_index.map do |store, index|
      Ec::SkuProduct.create!(
        sku_code: @sku.sku_code,
        store: store,
        product_id: "actual-product-#{index}-#{@token}",
        platform_sku_id: @platform_sku_ids[index].to_s
      )
    end
  end

  teardown do
    RawOzon::AccrualByDay.where(account_id: @accounts.map(&:id)).delete_all
    Ec::OperationLog.where(record_type: "Ec::SkuProduct", record_id: @products.map(&:id)).delete_all
    Ec::OperationLog.where(record_type: "Ec::Store", record_id: @stores.map(&:id)).delete_all
    Ec::OperationLog.where(record_type: "Ec::Sku", record_id: @sku.id).delete_all
    Ec::SkuProduct.where(id: @products.map(&:id)).delete_all
    Ec::Store.where(id: @stores.map(&:id)).delete_all
    RawOzon::SellerAccount.where(id: @accounts.map(&:id)).delete_all
    Ec::Sku.with_deleted.where(id: @sku.id).delete_all
  end

  test "returns posting-weighted outbound and return averages across bound Ozon stores" do
    create_accrual(0, type_id: 16, posting: "OUT-1", amount: -100, date: Date.new(2026, 8, 25))
    create_accrual(0, type_id: 28, posting: "OUT-1", amount: -20, date: Date.new(2026, 8, 25))
    create_accrual(0, type_id: 777, type_name: "LogisticService", posting: "OUT-2", amount: -80, date: Date.new(2026, 9, 1))
    create_accrual(0, type_id: 9, posting: "RET-1", amount: -40, date: Date.new(2026, 9, 2))
    create_accrual(0, type_id: 45, posting: "RET-1", amount: -10, date: Date.new(2026, 9, 2))
    create_accrual(1, type_id: 29, posting: "OUT-3", amount: -300, date: Date.new(2026, 9, 8))
    create_accrual(1, type_id: 888, type_name: "ReturnFlowService", posting: "RET-2", amount: -90, date: Date.new(2026, 9, 9))
    create_accrual(0, type_id: 12, posting: "SUPPLY-1", amount: -30, date: Date.new(2026, 9, 6))
    create_accrual(0, type_id: 12, posting: "SUPPLY-1", amount: -50, date: Date.new(2026, 9, 6))
    create_accrual(1, type_id: 12, posting: "SUPPLY-2", amount: -100, date: Date.new(2026, 9, 7))
    create_accrual(0, type_id: 12, posting: "WRONG-ACCOUNT-CROSS-DOCK", amount: -700, date: Date.new(2026, 9, 7), ozon_sku_id: @platform_sku_ids.fetch(1))
    create_accrual(0, type_id: 12, posting: "OUTSIDE-CROSS-DOCK", amount: -999, date: Date.new(2026, 8, 23))
    create_accrual(0, type_id: 12, posting: "ZERO-CROSS-DOCK", amount: 0, date: Date.new(2026, 9, 7))
    create_accrual(0, type_id: 16, posting: "WRONG-ACCOUNT", amount: -700, date: Date.new(2026, 9, 9), ozon_sku_id: @platform_sku_ids.fetch(1))
    create_accrual(1, type_id: 16, posting: nil, amount: -500, date: Date.new(2026, 9, 10))
    create_accrual(0, type_id: 16, posting: "OUTSIDE", amount: -999, date: Date.new(2026, 8, 23))
    create_accrual(0, type_id: 0, posting: "SALE-1", amount: 1_000, date: Date.new(2026, 9, 3))
    create_accrual(0, type_id: 0, posting: "SALE-2", amount: 900, date: Date.new(2026, 9, 4))
    create_accrual(1, type_id: 0, posting: "SALE-3", amount: 800, date: Date.new(2026, 9, 5))
    create_accrual(1, type_id: 0, posting: "RETURN-1", amount: -800, date: Date.new(2026, 9, 9))

    payload = Ec::SkuActualLogisticsQuery.run(
      sku: @sku,
      today: Date.new(2026, 9, 21)
    )

    assert_equal Date.new(2026, 8, 24), payload.dig(:period, :from_date)
    assert_equal Date.new(2026, 9, 20), payload.dig(:period, :to_date)
    assert_equal Date.new(2026, 9, 10), payload.dig(:period, :data_through)
    assert_equal 2, payload[:store_count]
    assert_equal 2, payload[:listing_count]
    assert_equal({ total_rub: 500.to_d, sample_count: 3, average_rub: 166.67.to_d }, payload[:outbound])
    assert_equal({ total_rub: 140.to_d, sample_count: 2, average_rub: 70.to_d }, payload[:return])
    assert_equal({ total_rub: 180.to_d, sample_count: 3, average_rub: 60.to_d }, payload[:cross_dock])
    assert_equal({ order_count: 3, return_count: 1, rate: 0.3333333333.to_d }, payload[:return_rate])
  end

  test "returns an empty cross-dock metric when the period has no charges" do
    payload = Ec::SkuActualLogisticsQuery.run(
      sku: @sku,
      today: Date.new(2026, 9, 21)
    )

    assert_equal({ total_rub: 0.to_d, sample_count: 0, average_rub: nil }, payload[:cross_dock])
  end

  private

  def create_accrual(account_index, type_id:, posting:, amount:, date:, type_name: "", ozon_sku_id: nil)
    RawOzon::AccrualByDay.create!(
      account_id: @accounts.fetch(account_index).id,
      accrual_date: date,
      accrued_category: "services",
      amount: amount,
      currency_code: "RUB",
      ozon_sku_id: ozon_sku_id || @platform_sku_ids.fetch(account_index),
      posting_number: posting,
      synced_at: Time.current,
      type_id: type_id,
      type_name: type_name
    )
  end
end
