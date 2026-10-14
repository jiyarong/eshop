require "test_helper"

class Ec::SkuActualAcquiringQueryTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(6).upcase
    @sku = Ec::Sku.create!(sku_code: "ACT-ACQ-#{@token}")
    @stores = []
    @products = []
    @ozon_accounts = []
    @wb_accounts = []
  end

  teardown do
    RawOzon::AccrualByDay.where(account_id: @ozon_accounts.map(&:id)).delete_all
    RawWb::FinanceDetail.where(account_id: @wb_accounts.map(&:id)).delete_all
    Ec::OperationLog.where(record_type: "Ec::SkuProduct", record_id: @products.map(&:id)).delete_all
    Ec::OperationLog.where(record_type: "Ec::Store", record_id: @stores.map(&:id)).delete_all
    Ec::OperationLog.where(record_type: "Ec::Sku", record_id: @sku.id).delete_all
    Ec::SkuProduct.where(id: @products.map(&:id)).delete_all
    Ec::Store.where(id: @stores.map(&:id)).delete_all
    RawOzon::SellerAccount.where(id: @ozon_accounts.map(&:id)).delete_all
    RawWb::SellerAccount.where(id: @wb_accounts.map(&:id)).delete_all
    Ec::Sku.with_deleted.where(id: @sku.id).delete_all
  end

  test "WB measures the acquiring fee on the sale rows' commission base, weighted by quantity" do
    account, nm_id = bind_wb
    day = Date.new(2026, 9, 1)
    wb_sale(account, nm_id, fee: 30, price: 1000, quantity: 1, date: day)
    wb_sale(account, nm_id, fee: 60, price: 1000, quantity: 2, date: day + 1)
    wb_sale(account, nm_id, fee: 99, price: 1000, quantity: 1, date: day - 20)
    wb_sale(account, nm_id + 1, fee: 99, price: 1000, quantity: 1, date: day)
    wb_sale(account, nm_id, fee: 99, price: 1000, quantity: 1, date: day, operation: "Логистика")

    payload = query("wb")

    assert_equal day + 1, payload.dig(:period, :data_through)
    assert_equal 90.to_d, payload.dig(:acquiring, :fee)
    assert_equal 3000.to_d, payload.dig(:acquiring, :base)
    assert_equal 2, payload.dig(:acquiring, :sample_count)
    assert_equal 0.03.to_d, payload.dig(:acquiring, :rate)
  end

  test "Ozon divides acquiring on postings that have revenue by SaleRevenue, returns netting both" do
    account, product_id = bind_ozon
    day = Date.new(2026, 9, 1)
    ozon_accrual(account, product_id, type_id: 0, amount: 1000, posting: "100-1-1", date: day)
    ozon_accrual(account, product_id, type_id: 1, amount: -20, posting: "100-1-1", date: day)
    ozon_accrual(account, product_id, type_id: 0, amount: 500, posting: "200-1-1", date: day)
    ozon_accrual(account, product_id, type_id: 1, amount: -10, posting: "200-1-1", date: day)
    ozon_accrual(account, product_id, type_id: 0, amount: -500, posting: "200-1-1", date: day + 2)
    ozon_accrual(account, product_id, type_id: 1, amount: 10, posting: "200-1-1", date: day + 2)
    # Acquiring of a posting that sold before the window is not part of this window's sales.
    ozon_accrual(account, product_id, type_id: 1, amount: -50, posting: "999-1-1", date: day)

    payload = query("ozon")

    assert_equal 20.to_d, payload.dig(:acquiring, :fee)
    assert_equal 1000.to_d, payload.dig(:acquiring, :base)
    assert_equal 0.02.to_d, payload.dig(:acquiring, :rate)
  end

  test "no sales means no rate" do
    bind_wb
    bind_ozon

    assert_nil query("wb").dig(:acquiring, :rate)
    assert_nil query("ozon").dig(:acquiring, :rate)
  end

  private

  def query(platform)
    Ec::SkuActualAcquiringQuery.run(sku: @sku, platform: platform, today: Date.new(2026, 9, 21))
  end

  def bind_ozon
    account = RawOzon::SellerAccount.create!(client_id: "acq-#{@token}", api_key: "key-#{@token}", company_name: "Acq #{@token}", company_type: "general")
    @ozon_accounts << account
    store = Ec::Store.create!(platform: "ozon", store_name: "Ozon #{@token}", company_type: "general", ozon_raw_account_id: account.id)
    bind(store, rand(10_000_000..19_999_999), :platform_sku_id).then { |id| [ account, id ] }
  end

  def bind_wb
    account = RawWb::SellerAccount.create!(api_token: "key-#{@token}", name: "Acq #{@token}", company_type: "general")
    @wb_accounts << account
    store = Ec::Store.create!(platform: "wb", store_name: "WB #{@token}", company_type: "general", wb_raw_account_id: account.id)
    bind(store, rand(20_000_000..29_999_999), :product_id).then { |id| [ account, id ] }
  end

  def bind(store, product_id, id_field)
    @stores << store
    @products << Ec::SkuProduct.create!(sku_code: @sku.sku_code, store: store, product_id: "product-#{@token}", platform_sku_id: "sku-#{@token}", id_field => product_id.to_s)
    product_id
  end

  def ozon_accrual(account, product_id, type_id:, amount:, date:, posting:)
    RawOzon::AccrualByDay.create!(account: account, ozon_sku_id: product_id, type_id: type_id, type_name: "", amount: amount,
      posting_number: posting, accrual_date: date, accrued_category: "services", currency_code: "RUB", synced_at: Time.current)
  end

  def wb_sale(account, nm_id, fee:, price:, quantity:, date:, operation: "Продажа")
    RawWb::FinanceDetail.create!(account: account, nm_id: nm_id, rrdid: rand(1_000_000_000..9_999_999_999), seller_oper_name: operation,
      acquiring_fee: fee, retail_price_with_disc: price, quantity: quantity, rr_dt: date)
  end
end
