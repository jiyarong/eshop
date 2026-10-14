require "test_helper"

class Ec::SkuActualScenarioPriceQueryTest < ActiveSupport::TestCase
  ZONE = ActiveSupport::TimeZone["Asia/Shanghai"]

  setup do
    @token = SecureRandom.hex(5).upcase
    @sku = Ec::Sku.create!(sku_code: "SCN-PR-#{@token}", product_name: "Scenario price")
    @stores = []
    @products = []
    @accounts = []
  end

  teardown do
    store_ids = @stores.map(&:id)
    Ec::OrderItem.where(store_id: store_ids).delete_all
    Ec::OrderFulfillment.where(store_id: store_ids).delete_all
    Ec::Order.where(store_id: store_ids).delete_all
    Ec::SkuProduct.where(id: @products.map(&:id)).delete_all
    Ec::Store.where(id: store_ids).delete_all
    @accounts.each(&:destroy!)
    Ec::Sku.with_deleted.where(id: @sku.id).delete_all
  end

  test "averages the commission base price of one WB scenario only, by tax regime and fulfillment" do
    small = wb_store("small", "71001")
    general = wb_store("general", "71002")
    day = Date.new(2026, 9, 2)
    order(small, "71001", price: 1000, quantity: 2, fulfillment_type: "fbw", date: day)
    order(small, "71001", price: 1300, quantity: 1, fulfillment_type: "fbw", date: day + 1)
    order(small, "71001", price: 5000, quantity: 1, fulfillment_type: "fbs", date: day)
    order(general, "71002", price: 9000, quantity: 1, fulfillment_type: "fbw", date: day)
    order(small, "71001", price: 7000, quantity: 1, fulfillment_type: "fbw", date: day, status: "cancelled")
    order(small, "71001", price: 7000, quantity: 1, fulfillment_type: "fbw", date: day - 30)

    fbo_small = query("wb", "ru", "fbo", "small").fetch(:commission_base_price)
    fbs_small = query("wb", "ru", "fbs", "small").fetch(:commission_base_price)
    fbo_general = query("wb", "ru", "fbo", "general").fetch(:commission_base_price)
    fbs_general = query("wb", "ru", "fbs", "general").fetch(:commission_base_price)

    # (1000 x 2 + 1300 x 1) / 3
    assert_equal BigDecimal("1100"), fbo_small.fetch(:average_rub)
    assert_equal 3, fbo_small.fetch(:unit_count)
    assert_equal BigDecimal("5000"), fbs_small.fetch(:average_rub)
    assert_equal BigDecimal("9000"), fbo_general.fetch(:average_rub)
    assert_nil fbs_general.fetch(:average_rub), "a scenario without orders of its own stays empty"
  end

  test "Ozon market is told apart by buyer currency and the store tax regime is not a filter" do
    store = ozon_store("small", "81001")
    day = Date.new(2026, 9, 2)
    order(store, "81001", price: 2000, quantity: 1, fulfillment_type: "fbo", date: day, buyer_currency: "RUB", platform: "ozon")
    order(store, "81001", price: 2400, quantity: 1, fulfillment_type: "fbo", date: day, buyer_currency: "BYN", platform: "ozon")
    order(store, "81001", price: 9999, quantity: 1, fulfillment_type: "fbs", date: day, buyer_currency: "RUB", platform: "ozon")

    assert_equal BigDecimal("2000"), query("ozon", "ru", "fbo", "general").dig(:commission_base_price, :average_rub)
    assert_equal BigDecimal("2400"), query("ozon", "by", "fbo", "general").dig(:commission_base_price, :average_rub)
  end

  private

  def query(platform, market, delivery_mode, company_type)
    Ec::SkuActualScenarioPriceQuery.run(
      sku: @sku, platform:, market:, delivery_mode:, company_type:, today: Date.new(2026, 9, 14), time_zone: ZONE
    )
  end

  def wb_store(company_type, nm_id)
    account = RawWb::SellerAccount.create!(name: "WB #{company_type} #{@token}", api_token: "token-#{company_type}-#{@token}", company_type: company_type.to_sym)
    @accounts << account
    store = Ec::Store.create!(platform: "wb", store_name: "WB #{company_type} #{@token}", company_type:, wb_raw_account_id: account.id)
    @stores << store
    @products << Ec::SkuProduct.create!(sku_code: @sku.sku_code, store: store, product_id: nm_id, product_name: "WB")
    store
  end

  def ozon_store(company_type, sku_id)
    account = RawOzon::SellerAccount.create!(company_name: "Ozon #{@token}", client_id: "client-#{@token}", api_key: "key", company_type: company_type.to_sym)
    @accounts << account
    store = Ec::Store.create!(platform: "ozon", store_name: "Ozon #{@token}", company_type:, ozon_raw_account_id: account.id)
    @stores << store
    @products << Ec::SkuProduct.create!(sku_code: @sku.sku_code, store: store, product_id: "OZ-#{@token}", platform_sku_id: sku_id, product_name: "Ozon")
    store
  end

  def order(store, platform_sku_id, price:, quantity:, fulfillment_type:, date:, status: "delivered", buyer_currency: nil, platform: "wb")
    key = "#{platform_sku_id}-#{date}-#{price}-#{status}-#{fulfillment_type}-#{SecureRandom.hex(3)}"
    order = Ec::Order.create!(store:, platform:, order_key: key, order_status: status,
      ordered_at: ZONE.local(date.year, date.month, date.day, 12))
    fulfillment = Ec::OrderFulfillment.create!(order:, store:, platform:, fulfillment_type:, status: "delivered",
      external_fulfillment_id: "f-#{key}", fulfillment_key: "f-#{key}")
    Ec::OrderItem.create!(order:, store:, platform:, platform_sku_id:, quantity:, unit_price: price, currency_code: "RUB",
      fulfillment_id: fulfillment.id, buyer_currency_code: buyer_currency)
  end
end
