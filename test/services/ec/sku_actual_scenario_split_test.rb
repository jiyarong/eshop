require "test_helper"

# The actual-data queries narrowed to one scenario: WB by target market (the buyer's country in the
# statistics orders, matched by srid), Ozon by FBO/FBS (the FBS posting table).
class Ec::SkuActualScenarioSplitTest < ActiveSupport::TestCase
  DAY = Date.new(2099, 9, 1)
  TODAY = DAY.beginning_of_week(:monday) + 4.weeks # the four full weeks before it contain DAY

  setup do
    @token = SecureRandom.hex(5).upcase
    @sku = Ec::Sku.create!(sku_code: "SPLIT-#{@token}")
    @wb_account = RawWb::SellerAccount.create!(api_token: "key-#{@token}", name: "Split WB #{@token}", company_type: "general")
    @wb_store = Ec::Store.create!(platform: "wb", store_name: "Split WB #{@token}", company_type: "general", wb_raw_account_id: @wb_account.id)
    @nm_id = rand(30_000_000..39_999_999)
    @ozon_account = RawOzon::SellerAccount.create!(client_id: "split-#{@token}", api_key: "key-#{@token}", company_name: "Split Ozon #{@token}", company_type: "general")
    @ozon_store = Ec::Store.create!(platform: "ozon", store_name: "Split Ozon #{@token}", company_type: "general", ozon_raw_account_id: @ozon_account.id)
    @ozon_sku_id = rand(40_000_000..49_999_999)
    @products = [
      Ec::SkuProduct.create!(sku_code: @sku.sku_code, store: @wb_store, product_id: @nm_id.to_s),
      Ec::SkuProduct.create!(sku_code: @sku.sku_code, store: @ozon_store, product_id: "oz-#{@token}", platform_sku_id: @ozon_sku_id.to_s)
    ]
    @rate = Ec::WeeklyRate.create!(week_start: DAY.beginning_of_week(:monday), rate_cny_rub: 10, rate_byn_rub: 25)
    @rrdid = rand(1_000_000_000..8_000_000_000)
  end

  teardown do
    RawWb::FinanceDetail.where(account_id: @wb_account.id).delete_all
    RawWb::StatsOrder.where(account_id: @wb_account.id).delete_all
    RawOzon::AccrualByDay.where(account_id: @ozon_account.id).delete_all
    RawOzon::PostingFbs.where(account_id: @ozon_account.id).delete_all
    Ec::OrderItem.where(store_id: [ @wb_store.id, @ozon_store.id ]).delete_all
    Ec::OrderFulfillment.where(store_id: [ @wb_store.id, @ozon_store.id ]).delete_all
    Ec::Order.where(store_id: [ @wb_store.id, @ozon_store.id ]).delete_all
    @rate.delete
    Ec::OperationLog.where(record_type: "Ec::SkuProduct", record_id: @products.map(&:id)).delete_all
    Ec::OperationLog.where(record_type: "Ec::Store", record_id: [ @wb_store.id, @ozon_store.id ]).delete_all
    Ec::OperationLog.where(record_type: "Ec::Sku", record_id: @sku.id).delete_all
    Ec::SkuProduct.where(id: @products.map(&:id)).delete_all
    Ec::Store.where(id: [ @wb_store.id, @ozon_store.id ]).delete_all
    RawWb::SellerAccount.where(id: @wb_account.id).delete_all
    RawOzon::SellerAccount.where(id: @ozon_account.id).delete_all
    Ec::Sku.with_deleted.where(id: @sku.id).delete_all
  end

  # ── WB: the market is the buyer's country, found through the srid ──────────────────────────

  test "WB logistics and return rate are measured per target market" do
    # Export to Russia (report_type 2): 2 outbound legs of 10 and 30 BYN, one return leg of 5.
    wb_leg("RU-1", "К клиенту при продаже", 10, report_type: 2)
    wb_leg("RU-2", "К клиенту при продаже", 30, report_type: 2)
    wb_leg("RU-1", "От клиента при возврате", 5, report_type: 2)
    # Belarus local (report_type 1): outbound 20, plus a cancelled parcel that comes back.
    wb_leg("BY-1", "К клиенту при продаже", 20, report_type: 1)
    wb_leg("BY-2", "К клиенту при отмене", 20, report_type: 1)
    wb_leg("BY-2", "От клиента при отмене", 8, report_type: 1)
    # A Russian buyer's cancelled parcel is booked in report type 1 too: it is a Russian parcel.
    wb_leg("RU-CANCEL", "К клиенту при отмене", 12, report_type: 1, country: "Россия")
    wb_leg("RU-CANCEL", "От клиента при отмене", 12, report_type: 1, country: "Россия")
    # Parcels with no statistics order (country unknown) belong to no market.
    wb_leg("UNKNOWN-CANCEL", "К клиенту при отмене", 50, report_type: 1, country: nil)
    wb_leg("UNKNOWN-CANCEL", "От клиента при отмене", 50, report_type: 1, country: nil)

    all = logistics(nil)
    ru = logistics("ru")
    by = logistics("by")

    assert_equal 6, all.dig(:outbound, :sample_count)
    # RU: legs 10 and 30 plus the Russian cancelled parcel's 12 BYN, all converted at 25.
    assert_equal({ total_rub: 1300.to_d, sample_count: 3, average_rub: 433.33.to_d }, ru[:outbound])
    assert_equal({ total_rub: 425.to_d, sample_count: 2, average_rub: 212.5.to_d }, ru[:return]) # 5 and 12 BYN
    assert_equal({ total_rub: 1000.to_d, sample_count: 2, average_rub: 500.to_d }, by[:outbound])
    assert_equal({ total_rub: 200.to_d, sample_count: 1, average_rub: 200.to_d }, by[:return])
    assert_equal "ru", ru[:market]

    rate = Ec::SkuActualReturnRateQuery.run(sku: @sku, platform: "wb", today: TODAY, time_zone: ActiveSupport::TimeZone["Asia/Shanghai"], delivery_mode: "fbo", market: "by")
    assert_equal({ order_count: 2, return_count: 1, rate: 0.5.to_d }, rate[:return_rate], "the Russian and unknown cancelled parcels are not Belarus's")
    assert_nil rate[:buyer_return_rate], "the orders table cannot tell the markets apart"
  end

  test "WB acquiring is measured per target market" do
    wb_sale("RU-1", price: 1000, acquiring: 30, report_type: 2)
    wb_sale("BY-1", price: 1000, acquiring: 19, report_type: 1)
    wb_sale("KZ-1", price: 1000, acquiring: 99, report_type: 1, country: "Казахстан") # neither market

    ru = Ec::SkuActualAcquiringQuery.run(sku: @sku, platform: "wb", today: TODAY, market: "ru")
    by = Ec::SkuActualAcquiringQuery.run(sku: @sku, platform: "wb", today: TODAY, market: "by")
    all = Ec::SkuActualAcquiringQuery.run(sku: @sku, platform: "wb", today: TODAY)

    assert_equal 0.03.to_d, ru.dig(:acquiring, :rate)
    assert_equal 0.019.to_d, by.dig(:acquiring, :rate)
    assert_equal ((30 + 19 + 99).to_d / 3000).round(10), all.dig(:acquiring, :rate)
  end

  test "a WB selling price is the one of the orders whose buyer is in that market; orders with no known country count as Russian and are reported" do
    wb_order("RU-A", price: 4000, quantity: 1)
    wb_order("BY-A", price: 3000, quantity: 1)
    wb_order("KZ-A", price: 7000, quantity: 1) # a country with no scenario
    wb_order("FRESH-A", price: 9000, quantity: 1) # no statistics order, so no known country
    wb_stats("RU-A", "Россия")
    wb_stats("BY-A", "Беларусь")
    wb_stats("KZ-A", "Казахстан")

    ru = price("wb", "ru", "fbo")
    by = price("wb", "by", "fbo")

    assert_equal 6500.to_d, ru.dig(:commission_base_price, :average_rub), "RU-A and the order with no known country; not the Kazakh one"
    assert_equal 3000.to_d, by.dig(:commission_base_price, :average_rub), "only what is known to be Belarusian"
    assert_equal 1, ru[:unclassified_unit_count]
  end

  test "a scenario price query also separates WB markets" do
    wb_order("RU-A", price: 4000, quantity: 2)
    wb_order("BY-A", price: 3000, quantity: 3)
    wb_stats("RU-A", "Россия")
    wb_stats("BY-A", "Беларусь")

    result = Ec::SkuActualScenarioPriceQuery.run(sku: @sku, platform: "wb", market: "by", delivery_mode: "fbo", company_type: "general",
      today: TODAY, time_zone: ActiveSupport::TimeZone["Asia/Shanghai"])

    assert_equal 3000.to_d, result.dig(:commission_base_price, :average_rub)
    assert_equal 3, result.dig(:commission_base_price, :unit_count)
  end

  # ── Ozon: FBO and FBS postings are told apart by the FBS posting table ────────────────────

  test "Ozon FBS splits its fees into the outbound leg, the hand-over and the return leg, FBO leaves the FBS postings out" do
    fbs_posting("FBS-1")
    fbs_posting("FBS-2")
    ozon_accrual(32, "FBS-1", -200)
    ozon_accrual(16, "FBS-1", -20)
    ozon_accrual(29, "FBS-1", -8)
    ozon_accrual(98, "FBS-1", -25)
    ozon_accrual(32, "FBS-2", -300)
    ozon_accrual(16, "FBS-2", -30)
    ozon_accrual(59, "FBS-2", -150)
    ozon_accrual(32, "FBO-1", -90)
    ozon_accrual(28, "FBO-1", -10)

    fbs = Ec::SkuActualLogisticsQuery.run(sku: @sku, platform: "ozon", delivery_mode: "fbs", today: TODAY)
    fbo = Ec::SkuActualLogisticsQuery.run(sku: @sku, platform: "ozon", delivery_mode: "fbo", today: TODAY)

    assert_equal({ total_rub: 500.to_d, sample_count: 2, average_rub: 250.to_d }, fbs[:outbound])
    assert_equal({ total_rub: 83.to_d, sample_count: 2, average_rub: 41.5.to_d }, fbs[:handover])
    assert_equal({ total_rub: 150.to_d, sample_count: 1, average_rub: 150.to_d }, fbs[:return])
    assert_equal({ order_count: 2, return_count: 1, rate: 0.5.to_d }, fbs[:return_rate])
    assert_nil fbs[:cross_dock], "FBS has no cross-docking"
    assert_equal({ total_rub: 100.to_d, sample_count: 1, average_rub: 100.to_d }, fbo[:outbound])
    assert_equal 0, fbo.dig(:handover, :sample_count)
    assert_equal "fbs", fbs[:delivery_mode]
  end

  test "Ozon FBS acquiring counts only FBS postings" do
    fbs_posting("FBS-1")
    ozon_accrual(0, "FBS-1", 1000)
    ozon_accrual(1, "FBS-1", -2)
    ozon_accrual(0, "FBO-1", 1000)
    ozon_accrual(1, "FBO-1", -20)

    fbs = Ec::SkuActualAcquiringQuery.run(sku: @sku, platform: "ozon", today: TODAY, delivery_mode: "fbs")
    fbo = Ec::SkuActualAcquiringQuery.run(sku: @sku, platform: "ozon", today: TODAY, delivery_mode: "fbo")

    assert_equal 0.002.to_d, fbs.dig(:acquiring, :rate)
    assert_equal 0.02.to_d, fbo.dig(:acquiring, :rate)
  end

  test "an Ozon selling price narrows to FBS orders" do
    ozon_order("FBS-ORD", price: 5000, fulfillment: "fbs", currency: "RUB")
    ozon_order("FBO-ORD", price: 3000, fulfillment: "fbo", currency: "RUB")

    fbs = price("ozon", "ru", "fbs")
    fbo = price("ozon", "ru", "fbo")
    both = price("ozon", "ru", nil)

    assert_equal 5000.to_d, fbs.dig(:commission_base_price, :average_rub)
    assert_equal 3000.to_d, fbo.dig(:commission_base_price, :average_rub)
    assert_equal 4000.to_d, both.dig(:commission_base_price, :average_rub)
  end

  # ── The scenario inputs ────────────────────────────────────────────────────────────────────

  test "scenario inputs carry the FBS hand-over and no storage for FBS" do
    fbs_posting("FBS-1")
    ozon_accrual(32, "FBS-1", -200)
    ozon_accrual(16, "FBS-1", -22)
    ozon_accrual(59, "FBS-1", -100)
    inputs = Ec::SkuProfitActualInputs.new(sku: @sku, today: TODAY, time_zone: ActiveSupport::TimeZone["Asia/Shanghai"])

    fbs = inputs.call(identity: { "platform" => "ozon", "market" => "ru", "delivery_mode" => "fbs", "warehouse_region" => "main", "company_type" => "general" }, exchange_rate: 13)
    fbo = inputs.call(identity: { "platform" => "ozon", "market" => "ru", "delivery_mode" => "fbo", "warehouse_region" => "main", "company_type" => "general" }, exchange_rate: 13)

    assert_equal 200.to_d, fbs[:values]["outbound_logistics_rub"]
    assert_equal 22.to_d, fbs[:values]["fbs_handover_rub"]
    assert_equal 100.to_d, fbs[:values]["return_logistics_rub"]
    assert_not fbs[:values].key?("storage_cny"), "FBS has no Ozon storage"
    assert_not fbo[:values].key?("fbs_handover_rub")
    assert_equal 0, fbo[:values].fetch("outbound_logistics_rub", 0), "the FBS postings are not FBO's"
  end

  private

  def logistics(market)
    Ec::SkuActualLogisticsQuery.run(sku: @sku, platform: "wb", delivery_mode: "fbo", market: market, today: TODAY)
  end

  def price(platform, market, mode)
    Ec::SkuActualSellingPriceQuery.run(sku: @sku, platform: platform, market: market, delivery_mode: mode, today: TODAY, time_zone: ActiveSupport::TimeZone["Asia/Shanghai"])
  end

  def wb_stats(srid, country)
    RawWb::StatsOrder.create!(account_id: @wb_account.id, srid: "#{srid}-#{@token}", order_date: DAY.in_time_zone, nm_id: @nm_id, country_name: country)
  end

  # The country of a parcel's order defaults to the one its report type usually means.
  def wb_country(report_type, country)
    country == :by_report_type ? { 2 => "Россия", 1 => "Беларусь" }.fetch(report_type) : country
  end

  def wb_leg(srid, bonus, amount, report_type:, country: :by_report_type)
    wb_stats(srid, wb_country(report_type, country)) if wb_country(report_type, country) && !RawWb::StatsOrder.exists?(account_id: @wb_account.id, srid: "#{srid}-#{@token}")
    RawWb::FinanceDetail.create!(account: @wb_account, nm_id: @nm_id, rrdid: (@rrdid += 1), rr_dt: DAY, sale_dt: DAY, srid: "#{srid}-#{@token}",
      seller_oper_name: "Логистика", bonus_type_name: bonus, delivery_method: "FBW, (МГТ, короба)", delivery_rub: amount, report_type: report_type)
  end

  def wb_sale(srid, price:, acquiring:, report_type:, country: :by_report_type)
    wb_stats(srid, wb_country(report_type, country)) if wb_country(report_type, country)
    RawWb::FinanceDetail.create!(account: @wb_account, nm_id: @nm_id, rrdid: (@rrdid += 1), rr_dt: DAY, sale_dt: DAY, srid: "#{srid}-#{@token}",
      seller_oper_name: "Продажа", quantity: 1, retail_price_with_disc: price, acquiring_fee: acquiring, report_type: report_type)
  end

  def wb_order(srid, price:, quantity:)
    order = Ec::Order.create!(store: @wb_store, platform: "wb", order_key: "wb:#{@wb_store.id}:#{srid}-#{@token}", external_order_id: "#{srid}-#{@token}",
      order_status: "delivered", ordered_at: ActiveSupport::TimeZone["Asia/Shanghai"].local(DAY.year, DAY.month, DAY.day, 12))
    fulfillment = Ec::OrderFulfillment.create!(order:, store: @wb_store, platform: "wb", fulfillment_type: "fbo", status: "delivered",
      external_fulfillment_id: "f-#{srid}-#{@token}", fulfillment_key: "f-#{srid}-#{@token}")
    Ec::OrderItem.create!(order:, store: @wb_store, platform: "wb", platform_sku_id: @nm_id.to_s, quantity:, unit_price: price, currency_code: "RUB",
      buyer_paid_unit_price: price, buyer_currency_code: "RUB", fulfillment_id: fulfillment.id)
  end

  def ozon_order(srid, price:, fulfillment:, currency:)
    order = Ec::Order.create!(store: @ozon_store, platform: "ozon", order_key: "ozon:#{@ozon_store.id}:#{srid}-#{@token}", external_order_id: "#{srid}-#{@token}",
      order_status: "delivered", ordered_at: ActiveSupport::TimeZone["Asia/Shanghai"].local(DAY.year, DAY.month, DAY.day, 12))
    row = Ec::OrderFulfillment.create!(order:, store: @ozon_store, platform: "ozon", fulfillment_type: fulfillment, status: "delivered",
      external_fulfillment_id: "f-#{srid}-#{@token}", fulfillment_key: "f-#{srid}-#{@token}")
    Ec::OrderItem.create!(order:, store: @ozon_store, platform: "ozon", platform_sku_id: @ozon_sku_id.to_s, quantity: 1, unit_price: price, currency_code: "RUB",
      buyer_paid_unit_price: price, buyer_currency_code: currency, fulfillment_id: row.id)
  end

  def fbs_posting(number)
    RawOzon::PostingFbs.create!(account_id: @ozon_account.id, posting_number: number, raw_json: {}, status: "delivered")
  end

  def ozon_accrual(type_id, posting, amount)
    RawOzon::AccrualByDay.create!(account_id: @ozon_account.id, accrual_date: DAY, accrued_category: "services", amount: amount, currency_code: "RUB",
      ozon_sku_id: @ozon_sku_id, posting_number: posting, synced_at: Time.current, type_id: type_id, type_name: type_id.zero? ? "SaleRevenue" : "")
  end
end
