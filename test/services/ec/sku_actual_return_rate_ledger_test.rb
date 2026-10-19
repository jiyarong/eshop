require "test_helper"

# The return rate is counted in logistics legs on both platforms: return legs billed per outbound
# leg billed. That is the rate the calculator's amortization (outbound + return) x r / (1 - r)
# needs to reproduce the profit attribution's logistics cost.
class Ec::SkuActualReturnRateLedgerTest < ActiveSupport::TestCase
  TODAY = Date.new(2093, 9, 21) # window: 2093-08-24 .. 2093-09-20
  OUTBOUND = "К клиенту при продаже".freeze
  OUTBOUND_CANCELLED = "К клиенту при отмене".freeze
  RETURN = "От клиента при возврате".freeze
  RETURN_CANCELLED = "От клиента при отмене".freeze
  TO_SELLER = "Возврат брака (К продавцу)".freeze

  setup do
    @token = SecureRandom.hex(5).upcase
    @time_zone = ActiveSupport::TimeZone["Asia/Shanghai"]
    @sku = Ec::Sku.create!(sku_code: "ACT-RR-LEDGER-#{@token}")
    @account = RawWb::SellerAccount.create!(api_token: "key-#{@token}", name: "Return ledger #{@token}", company_type: "general")
    @store = Ec::Store.create!(platform: "wb", store_name: "WB return ledger #{@token}", company_type: "general", wb_raw_account_id: @account.id)
    @nm_id = rand(30_000_000..39_999_999)
    @product = Ec::SkuProduct.create!(
      sku_code: @sku.sku_code, store: @store, product_id: @nm_id.to_s, platform_sku_id: "sku-#{@token}"
    )
    @weeks = (0..3).map { |index| Date.new(2093, 8, 24) + index * 7 }
    @weeks.each do |week|
      Ec::WeeklyRate.create!(week_start: week, rate_cny_rub: 12, rate_byn_rub: 27) unless Ec::WeeklyRate.exists?(week_start: week)
    end
    @created_rates = @weeks
  end

  teardown do
    RawWb::FinanceDetail.where(account_id: @account.id).delete_all
    Ec::WeeklyRate.where(week_start: @created_rates).where(rate_cny_rub: 12, rate_byn_rub: 27).delete_all
    Ec::OperationLog.where(record_type: "Ec::SkuProduct", record_id: @product.id).delete_all
    Ec::OperationLog.where(record_type: "Ec::Store", record_id: @store.id).delete_all
    Ec::OperationLog.where(record_type: "Ec::Sku", record_id: @sku.id).delete_all
    Ec::SkuProduct.where(id: @product.id).delete_all
    Ec::Store.where(id: @store.id).delete_all
    RawWb::SellerAccount.where(id: @account.id).delete_all
    Ec::Sku.with_deleted.where(id: @sku.id).delete_all
  end

  test "WB counts return legs per outbound leg, cancelled parcels included" do
    7.times { |index| leg(OUTBOUND, "S#{index}") }
    leg(OUTBOUND_CANCELLED, "C1")
    leg(RETURN, "S0")
    leg(RETURN_CANCELLED, "C1")

    payload = query

    assert_equal 8, payload.dig(:return_rate, :order_count)
    assert_equal 2, payload.dig(:return_rate, :return_count)
    assert_equal 0.25.to_d, payload.dig(:return_rate, :rate)
    assert_equal 1, payload[:store_count]
    assert_equal Date.new(2093, 8, 24), payload.dig(:period, :from_date)
    assert_equal Date.new(2093, 9, 20), payload.dig(:period, :to_date)
  end

  test "parcels returned to the seller do not count as customer returns" do
    4.times { |index| leg(OUTBOUND, "S#{index}") }
    leg(TO_SELLER, "SELLER-1")

    payload = query

    assert_equal 4, payload.dig(:return_rate, :order_count)
    assert_equal 0, payload.dig(:return_rate, :return_count)
    assert_equal 0.to_d, payload.dig(:return_rate, :rate)
  end

  test "a delivery mode narrows the legs to FBW or FBS" do
    3.times { |index| leg(OUTBOUND, "W#{index}", method: "FBW") }
    leg(RETURN, "W0", method: "FBW")
    5.times { |index| leg(OUTBOUND, "B#{index}", method: "FBS") }

    assert_equal 0.3333333333.to_d, query(delivery_mode: "fbo").dig(:return_rate, :rate)
    assert_equal 0.to_d, query(delivery_mode: "fbs").dig(:return_rate, :rate)
    assert_equal 0.125.to_d, query.dig(:return_rate, :rate)
  end

  test "legs outside the four weeks and of other SKUs are ignored" do
    2.times { |index| leg(OUTBOUND, "S#{index}") }
    leg(RETURN, "OLD", date: Date.new(2093, 8, 20))
    leg(RETURN, "OTHER", nm_id: @nm_id + 1)

    payload = query

    assert_equal 2, payload.dig(:return_rate, :order_count)
    assert_equal 0, payload.dig(:return_rate, :return_count)
  end

  test "has no rate without outbound legs" do
    payload = query

    assert_equal 0, payload.dig(:return_rate, :order_count)
    assert_nil payload.dig(:return_rate, :rate)
  end

  private

  def query(delivery_mode: nil)
    Ec::SkuActualReturnRateQuery.run(
      sku: @sku, platform: "wb", today: TODAY, time_zone: @time_zone, delivery_mode: delivery_mode
    )
  end

  def leg(bonus_type, reference, method: "FBW", date: Date.new(2093, 9, 2), nm_id: @nm_id)
    RawWb::FinanceDetail.create!(
      account: @account, wb_report_id: 1, nm_id: nm_id, rrdid: rand(1_000_000_000..9_999_999_999), rr_dt: date,
      seller_oper_name: "Логистика", bonus_type_name: bonus_type, delivery_method: method, delivery_rub: 40,
      srid: "#{reference}-#{@token}", shk_id: rand(1_000_000..9_999_999), report_type: 2, quantity: 1
    )
  end
end
