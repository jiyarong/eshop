require "test_helper"

class Ec::SkuScenarioSalesTest < ActiveSupport::TestCase
  ZONE = ActiveSupport::TimeZone["Asia/Shanghai"]
  TODAY = Date.new(2026, 10, 14) # Wednesday; the window starts Monday 2026-07-27

  setup do
    @token = SecureRandom.hex(5).upcase
    @sku = Ec::Sku.create!(sku_code: "SCS-#{@token}")
    @other_sku = Ec::Sku.create!(sku_code: "SCS-OTHER-#{@token}")
    @stores = []
    @products = []
    @accounts = []
    @rrdid = rand(1_000_000_000..9_000_000_000)
  end

  teardown do
    store_ids = @stores.map(&:id)
    RawWb::FinanceDetail.where(account_id: @accounts.select { |a| a.is_a?(RawWb::SellerAccount) }.map(&:id)).delete_all
    Ec::OrderItem.where(store_id: store_ids).delete_all
    Ec::OrderFulfillment.where(store_id: store_ids).delete_all
    Ec::Order.where(store_id: store_ids).delete_all
    Ec::OperationLog.where(record_type: "Ec::SkuProduct", record_id: @products.map(&:id)).delete_all
    Ec::OperationLog.where(record_type: "Ec::Store", record_id: store_ids).delete_all
    Ec::SkuProduct.where(id: @products.map(&:id)).delete_all
    Ec::Store.where(id: store_ids).delete_all
    @accounts.each(&:destroy!)
    Ec::OperationLog.where(record_type: "Ec::Sku", record_id: [ @sku.id, @other_sku.id ]).delete_all
    Ec::Sku.with_deleted.where(id: [ @sku.id, @other_sku.id ]).delete_all
  end

  test "the window is twelve weeks counted from this week's Monday" do
    result = call

    assert_equal Date.new(2026, 7, 27), result[:from_date]
    assert_equal TODAY, result[:to_date]
    assert_equal Ec::SkuProfitStandardContexts.scenario_keys.sort, result[:scenarios].keys.sort
    assert result[:scenarios].values.all? { |entry| entry[:units].zero? }
    assert_equal 0, result[:total_units]
  end

  test "Ozon counts delivered units by fulfillment and buyer currency" do
    store = ozon_store("81001")
    ozon_order(store, "81001", quantity: 3, fulfillment: "fbo", currency: "RUB", date: Date.new(2026, 9, 2))
    ozon_order(store, "81001", quantity: 2, fulfillment: "fbo", currency: "RUB", date: Date.new(2026, 9, 9))
    ozon_order(store, "81001", quantity: 4, fulfillment: "fbo", currency: "BYN", date: Date.new(2026, 9, 2))
    ozon_order(store, "81001", quantity: 6, fulfillment: "fbs", currency: "RUB", date: Date.new(2026, 9, 2))
    ozon_order(store, "81001", quantity: 9, fulfillment: "fbo", currency: "RUB", date: Date.new(2026, 9, 2), status: "cancelled")
    ozon_order(store, "81001", quantity: 8, fulfillment: "fbo", currency: "RUB", date: Date.new(2026, 9, 2), status: "shipped")
    ozon_order(store, "81001", quantity: 7, fulfillment: "fbo", currency: "RUB", date: Date.new(2026, 7, 20)) # before the window
    ozon_order(store, "81001", quantity: 5, fulfillment: "fbo", currency: nil, date: Date.new(2026, 9, 2))

    result = call

    ru = result[:scenarios].fetch("ozon|ru|fbo|main|general")
    assert_equal 5, ru[:units]
    assert_equal 2, ru[:orders]
    assert_equal Date.new(2026, 9, 9), ru[:last_date]
    assert_equal 4, result[:scenarios].fetch("ozon|by|fbo|main|general")[:units]
    assert_equal 6, result[:outside_units], "Ozon FBS is not one of the standard scenarios yet"
    assert_equal 5, result[:unclassified_units], "a missing buyer currency says nothing about the market"
    assert_equal 20, result[:total_units]
  end

  test "WB tells the market from the report type, the fulfillment from the logistics rows and the tax from the account" do
    small = wb_store("small", "71001")
    general = wb_store("general", "71002")
    wb_sale(small, 71_001, srid: "A", quantity: 2, report_type: 2, mode: "FBW, (МГТ, короба)")
    wb_sale(small, 71_001, srid: "B", quantity: 1, report_type: 2, mode: "FBS, (МГТ)")
    wb_sale(small, 71_001, srid: "C", quantity: 4, report_type: 1, mode: "FBS, (МГТ)")
    wb_sale(general, 71_002, srid: "D", quantity: 3, report_type: 2, mode: "FBS")
    wb_sale(small, 71_001, srid: "E", quantity: 5, report_type: 2, mode: nil)
    wb_sale(small, 71_001, srid: "F", quantity: 6, report_type: 2, mode: "FBS", date: Date.new(2026, 7, 20))
    wb_sale(small, 71_001, srid: "G", quantity: 7, report_type: 2, mode: "FBS", operation: "Возврат")
    wb_sale(small, 71_999, srid: "H", quantity: 8, report_type: 2, mode: "FBS") # not a listing of this SKU

    result = call

    assert_equal 2, result[:scenarios].fetch("wb|ru|fbo|main|small")[:units]
    assert_equal 1, result[:scenarios].fetch("wb|ru|fbs|main|small")[:units]
    assert_equal 3, result[:scenarios].fetch("wb|ru|fbs|main|general")[:units]
    assert_equal 4, result[:outside_units], "Belarus-local WB sales belong to a scenario the workbench does not have yet"
    assert_equal 5, result[:unclassified_units], "a sale row without a logistics row cannot be told FBW from FBS"
    assert_equal 15, result[:total_units]
  end

  test "units of another SKU are not counted" do
    store = ozon_store("81001")
    other = Ec::SkuProduct.create!(sku_code: @other_sku.sku_code, store: store, product_id: "OZ-OTHER-#{@token}", platform_sku_id: "81002", product_name: "other")
    @products << other
    ozon_order(store, "81002", quantity: 9, fulfillment: "fbo", currency: "RUB", date: Date.new(2026, 9, 2))
    ozon_order(store, "81001", quantity: 1, fulfillment: "fbo", currency: "RUB", date: Date.new(2026, 9, 2))

    assert_equal 1, call[:total_units]
  end

  test "an SKU without listings sells nothing and does not fail" do
    assert_equal 0, call[:total_units]
  end

  private

  def call
    Ec::SkuScenarioSales.call(sku: @sku, today: TODAY, time_zone: ZONE)
  end

  def ozon_store(platform_sku_id)
    account = RawOzon::SellerAccount.create!(company_name: "Ozon #{@token}", client_id: "client-#{@token}", api_key: "key", company_type: :general)
    @accounts << account
    store = Ec::Store.create!(platform: "ozon", store_name: "Ozon #{@token}", company_type: "general", ozon_raw_account_id: account.id)
    @stores << store
    @products << Ec::SkuProduct.create!(sku_code: @sku.sku_code, store: store, product_id: "OZ-#{@token}", platform_sku_id: platform_sku_id, product_name: "Ozon")
    store
  end

  def ozon_order(store, platform_sku_id, quantity:, fulfillment:, currency:, date:, status: "delivered")
    key = "#{platform_sku_id}-#{date}-#{quantity}-#{status}-#{fulfillment}-#{SecureRandom.hex(3)}"
    order = Ec::Order.create!(store:, platform: "ozon", order_key: key, order_status: status, ordered_at: ZONE.local(date.year, date.month, date.day, 12))
    fulfillment_row = Ec::OrderFulfillment.create!(order:, store:, platform: "ozon", fulfillment_type: fulfillment, status: "delivered",
      external_fulfillment_id: "f-#{key}", fulfillment_key: "f-#{key}")
    Ec::OrderItem.create!(order:, store:, platform: "ozon", platform_sku_id:, quantity:, unit_price: 1000, currency_code: "RUB",
      fulfillment_id: fulfillment_row.id, buyer_currency_code: currency)
  end

  def wb_store(company_type, nm_id)
    account = RawWb::SellerAccount.create!(name: "WB #{company_type} #{@token}", api_token: "token-#{company_type}-#{@token}", company_type: company_type.to_sym)
    @accounts << account
    store = Ec::Store.create!(platform: "wb", store_name: "WB #{company_type} #{@token}", company_type:, wb_raw_account_id: account.id)
    @stores << store
    @products << Ec::SkuProduct.create!(sku_code: @sku.sku_code, store: store, product_id: nm_id, product_name: "WB")
    store
  end

  def wb_sale(store, nm_id, srid:, quantity:, report_type:, mode:, date: Date.new(2026, 9, 2), operation: "Продажа")
    account_id = store.wb_raw_account_id
    RawWb::FinanceDetail.create!(account_id:, rrdid: (@rrdid += 1), nm_id:, srid: "#{srid}-#{@token}", seller_oper_name: operation,
      quantity:, report_type:, rr_dt: date)
    return unless mode

    RawWb::FinanceDetail.create!(account_id:, rrdid: (@rrdid += 1), nm_id:, srid: "#{srid}-#{@token}", seller_oper_name: "Логистика",
      bonus_type_name: "К клиенту при продаже", delivery_method: mode, delivery_rub: 10, rr_dt: date, report_type:)
  end
end
