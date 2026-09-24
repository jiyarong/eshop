require "test_helper"

class Ec::SkuActualStorageQueryTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(6).upcase
    @sku = Ec::Sku.create!(sku_code: "ACT-STO-#{@token}")
    @stores = []
    @products = []
    @ozon_accounts = []
    @wb_accounts = []
  end

  teardown do
    RawOzon::AccrualByDay.where(account_id: @ozon_accounts.map(&:id)).delete_all
    RawWb::PaidStorage.where(account_id: @wb_accounts.map(&:id)).delete_all
    RawWb::FinanceDetail.where(account_id: @wb_accounts.map(&:id)).delete_all
    RawWb::SalesReport.where(account_id: @wb_accounts.map(&:id)).delete_all
    Ec::OperationLog.where(record_type: "Ec::SkuProduct", record_id: @products.map(&:id)).delete_all
    Ec::OperationLog.where(record_type: "Ec::Store", record_id: @stores.map(&:id)).delete_all
    Ec::OperationLog.where(record_type: "Ec::Sku", record_id: @sku.id).delete_all
    Ec::SkuProduct.where(id: @products.map(&:id)).delete_all
    Ec::Store.where(id: @stores.map(&:id)).delete_all
    RawOzon::SellerAccount.where(id: @ozon_accounts.map(&:id)).delete_all
    RawWb::SellerAccount.where(id: @wb_accounts.map(&:id)).delete_all
    Ec::Sku.with_deleted.where(id: @sku.id).delete_all
  end

  test "Ozon uses net storage charges per positive posting and excludes cross-dock" do
    account, product_id = bind_ozon
    day = Date.new(2026, 9, 1)
    ozon_accrual(account, product_id, type_id: 15, amount: -120, date: day)
    ozon_accrual(account, product_id, type_id: 46, amount: 20, date: day)
    ozon_accrual(account, product_id, type_id: 789, type_name: "ReturnStorageFee", amount: -50, date: day)
    ozon_accrual(account, product_id, type_id: 12, amount: -100, date: day)
    ozon_accrual(account, product_id + 1, type_id: 15, amount: -900, date: day)
    ozon_accrual(account, product_id, type_id: 15, amount: -900, date: day - 10)
    ozon_accrual(account, product_id, type_id: 0, amount: 500, posting: "SALE-1", date: day)
    ozon_accrual(account, product_id, type_id: 0, amount: 100, posting: "SALE-1", date: day)
    ozon_accrual(account, product_id, type_id: 0, amount: 400, posting: "SALE-2", date: day)
    ozon_accrual(account, product_id, type_id: 0, amount: -400, posting: "RETURN-1", date: day)

    payload = query("ozon")
    assert_equal 1, payload[:store_count]
    assert_equal 1, payload[:listing_count]
    assert_equal day, payload.dig(:period, :data_through)
    assert_equal({ total_rub: 150.to_d, sample_count: 3, sale_count: 2, average_rub: 75.to_d }, payload[:storage])
  end

  test "WB divides net paid storage by same-period export sales quantity" do
    account, product_id = bind_wb
    day = Date.new(2026, 9, 1)
    wb_storage(account, product_id, -30, day)
    wb_storage(account, product_id, 90, day + 1)
    wb_storage(account, product_id + 1, 500, day)
    wb_storage(account, product_id, 500, day - 10)

    report = RawWb::SalesReport.create!(account: account, wb_report_id: random_id, date_from: day, date_to: day + 6)
    wb_sale(account, report, product_id, quantity: 2, report_type: 2)
    wb_sale(account, report, product_id, quantity: 1, report_type: 2)
    wb_sale(account, report, product_id, quantity: 8, report_type: 1)
    wb_sale(account, report, product_id + 1, quantity: 10, report_type: 2)

    payload = query("wb")
    assert_equal day + 1, payload.dig(:period, :data_through)
    assert_equal({ total_rub: 60.to_d, sample_count: 2, sale_count: 3, average_rub: 20.to_d }, payload[:storage])
  end

  test "does not offer a per-sale amount without both charges and sales" do
    account, product_id = bind_wb
    wb_storage(account, product_id, 50, Date.new(2026, 9, 1))
    assert_equal({ total_rub: 50.to_d, sample_count: 1, sale_count: 0, average_rub: nil }, query("wb")[:storage])
    assert_nil query("ozon").dig(:storage, :average_rub)
  end

  test "Ozon refunds exceeding charges do not become a positive storage cost" do
    account, product_id = bind_ozon
    day = Date.new(2026, 9, 1)
    ozon_accrual(account, product_id, type_id: 15, amount: -30, date: day)
    ozon_accrual(account, product_id, type_id: 15, amount: 50, date: day)
    ozon_accrual(account, product_id, type_id: 0, amount: 500, posting: "SALE", date: day)

    assert_equal({ total_rub: 0.to_d, sample_count: 2, sale_count: 1, average_rub: nil }, query("ozon")[:storage])
  end

  private

  def query(platform)
    Ec::SkuActualStorageQuery.run(sku: @sku, platform: platform, today: Date.new(2026, 9, 21))
  end

  def bind_ozon
    account = RawOzon::SellerAccount.create!(client_id: "storage-#{@token}", api_key: "key-#{@token}", company_name: "Storage #{@token}", company_type: "general")
    @ozon_accounts << account
    store = Ec::Store.create!(platform: "ozon", store_name: "Ozon #{@token}", company_type: "general", ozon_raw_account_id: account.id)
    bind(store, rand(10_000_000..19_999_999), :platform_sku_id).then { |id| [account, id] }
  end

  def bind_wb
    account = RawWb::SellerAccount.create!(api_token: "key-#{@token}", name: "Storage #{@token}", company_type: "general")
    @wb_accounts << account
    store = Ec::Store.create!(platform: "wb", store_name: "WB #{@token}", company_type: "general", wb_raw_account_id: account.id)
    bind(store, rand(20_000_000..29_999_999), :product_id).then { |id| [account, id] }
  end

  def bind(store, product_id, id_field)
    @stores << store
    @products << Ec::SkuProduct.create!(sku_code: @sku.sku_code, store: store, product_id: "product-#{@token}", platform_sku_id: "sku-#{@token}", id_field => product_id.to_s)
    product_id
  end

  def ozon_accrual(account, product_id, type_id:, amount:, date:, posting: nil, type_name: "")
    RawOzon::AccrualByDay.create!(account: account, ozon_sku_id: product_id, type_id: type_id, type_name: type_name, amount: amount,
      posting_number: posting, accrual_date: date, accrued_category: "services", currency_code: "RUB", synced_at: Time.current)
  end

  def wb_storage(account, product_id, amount, date)
    RawWb::PaidStorage.create!(account: account, nm_id: product_id, warehouse_price_rub: amount, calc_date: date)
  end

  def wb_sale(account, report, product_id, quantity:, report_type:)
    RawWb::FinanceDetail.create!(account: account, wb_report_id: report.wb_report_id, nm_id: product_id, rrdid: random_id,
      seller_oper_name: "Продажа", report_type: report_type, quantity: quantity)
  end

  def random_id
    rand(1_000_000_000..9_999_999_999)
  end
end
