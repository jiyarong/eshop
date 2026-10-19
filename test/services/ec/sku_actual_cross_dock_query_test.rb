require "test_helper"

class Ec::SkuActualCrossDockQueryTest < ActiveSupport::TestCase
  TODAY = Date.new(2026, 10, 19) # window: 2026-07-27 .. 2026-10-18 (12 full weeks)

  setup do
    @token = SecureRandom.hex(5).upcase
    @sku = Ec::Sku.create!(sku_code: "ACT-XD-#{@token}")
    @account = RawOzon::SellerAccount.create!(
      client_id: "actual-xd-#{@token}", api_key: "key-#{@token}", company_name: "Actual cross-dock", company_type: "general"
    )
    @other_account = RawOzon::SellerAccount.create!(
      client_id: "actual-xd-other-#{@token}", api_key: "key-#{@token}", company_name: "Other cross-dock", company_type: "general"
    )
    @store = Ec::Store.create!(
      platform: "ozon", store_name: "Actual cross-dock #{@token}", company_type: "general", ozon_raw_account_id: @account.id
    )
    @ozon_sku = rand(10_000_000..19_999_999)
    @other_ozon_sku = @ozon_sku + 1
    @product = Ec::SkuProduct.create!(
      sku_code: @sku.sku_code, store: @store, product_id: "actual-xd-product-#{@token}", platform_sku_id: @ozon_sku.to_s
    )
    @supply_number = 2_000_000_000_000 + rand(1_000_000)
  end

  teardown do
    accounts = [@account.id, @other_account.id]
    order_ids = RawOzon::SupplyOrder.where(account_id: accounts).ids
    RawOzon::SupplyOrderItem.where(supply_order_id: order_ids).delete_all
    RawOzon::SupplyOrder.where(id: order_ids).delete_all
    RawOzon::AccrualByDay.where(account_id: accounts).delete_all
    Ec::OperationLog.where(record_type: "Ec::SkuProduct", record_id: @product.id).delete_all
    Ec::OperationLog.where(record_type: "Ec::Store", record_id: @store.id).delete_all
    Ec::OperationLog.where(record_type: "Ec::Sku", record_id: @sku.id).delete_all
    Ec::SkuProduct.where(id: @product.id).delete_all
    Ec::Store.where(id: @store.id).delete_all
    RawOzon::SellerAccount.where(id: accounts).delete_all
    Ec::Sku.with_deleted.where(id: @sku.id).delete_all
  end

  test "divides the fees of the supplies by the units those supplies carried, not by the fee lines" do
    supply = create_supply(30, accrued: Date.new(2026, 9, 1))
    fee_lines(supply, [-300, -300, -300], Date.new(2026, 9, 1))
    second = create_supply(10, accrued: Date.new(2026, 9, 10))
    fee_lines(second, [-250], Date.new(2026, 9, 10))

    payload = run_query(min_units: 1)

    assert_equal 1_150.to_d, payload[:total_rub]
    assert_equal 40, payload[:unit_count]
    assert_equal 2, payload[:sample_count]
    # 1150 / 40 units, where the "average fee line" would be 287.5
    assert_equal 28.75.to_d, payload[:average_rub]
    assert_equal Date.new(2026, 9, 10), payload[:data_through]
    assert_equal Date.new(2026, 7, 27), payload[:from_date]
    assert_equal Date.new(2026, 10, 18), payload[:to_date]
    assert_equal false, payload[:expanded_to_all_history]
  end

  test "counts only this SKU's units of a supply that carries other SKUs" do
    supply = create_supply(10, accrued: Date.new(2026, 9, 1))
    create_item(supply[:order], @other_ozon_sku, 90, supply_id: supply[:id])
    fee_lines(supply, [-100, -100], Date.new(2026, 9, 1))

    payload = run_query(min_units: 1)

    assert_equal 10, payload[:unit_count]
    assert_equal 20.to_d, payload[:average_rub]
  end

  test "units that arrived by direct supply carry no fee but share the average" do
    supply = create_supply(30, accrued: Date.new(2026, 9, 1))
    fee_lines(supply, [-600], Date.new(2026, 9, 1))
    direct = create_supply(10, accrued: nil, crossdock: false, created_at: Time.utc(2026, 9, 5))
    create_supply(50, accrued: nil, crossdock: false, created_at: Time.utc(2026, 5, 1)) # outside the window

    payload = run_query(min_units: 1)

    assert_equal 30, payload[:unit_count]
    assert_equal 10, payload[:direct_unit_count]
    assert_equal 15.to_d, payload[:average_rub] # 600 / (30 + 10)
    assert direct
  end

  test "cancelled direct supplies are not counted" do
    supply = create_supply(10, accrued: Date.new(2026, 9, 1))
    fee_lines(supply, [-100], Date.new(2026, 9, 1))
    create_supply(10, accrued: nil, crossdock: false, created_at: Time.utc(2026, 9, 5), order_status: "CANCELLED")

    assert_equal 0, run_query(min_units: 1)[:direct_unit_count]
  end

  test "a window with too few units widens to all history" do
    recent = create_supply(5, accrued: Date.new(2026, 9, 1))
    fee_lines(recent, [-500], Date.new(2026, 9, 1)) # 100 per unit
    old = create_supply(20, accrued: Date.new(2026, 3, 1))
    fee_lines(old, [-1_000], Date.new(2026, 3, 1)) # 50 per unit

    narrow = run_query(min_units: 5)
    assert_equal 5, narrow[:unit_count]
    assert_equal 100.to_d, narrow[:average_rub]
    assert_equal false, narrow[:expanded_to_all_history]

    widened = run_query(min_units: 20)
    assert_equal 25, widened[:unit_count]
    assert_equal 60.to_d, widened[:average_rub] # 1500 / 25
    assert_equal true, widened[:expanded_to_all_history]
    assert_equal Date.new(2026, 3, 1), widened[:from_date]
  end

  test "fees of supplies without item rows are reported but not used" do
    supply = create_supply(10, accrued: Date.new(2026, 9, 1))
    fee_lines(supply, [-100], Date.new(2026, 9, 1))
    lost_number = @supply_number + 99
    accrual(lost_number, -400, Date.new(2026, 9, 2))
    accrual(nil, -50, Date.new(2026, 9, 3))

    payload = run_query(min_units: 1)

    assert_equal 10.to_d, payload[:average_rub]
    assert_equal 100.to_d, payload[:total_rub]
    assert_equal 2, payload[:unmatched_supply_count]
    assert_equal 450.to_d, payload[:unmatched_fee_rub]
  end

  test "another account's supply with the same number is not borrowed" do
    supply = create_supply(10, accrued: Date.new(2026, 9, 1))
    fee_lines(supply, [-100], Date.new(2026, 9, 1))
    foreign = RawOzon::SupplyOrder.create!(
      account_id: @other_account.id, supply_order_id: "F#{@token}", status: "COMPLETED", raw_json: {}, created_at: Time.utc(2026, 9, 1)
    )
    create_item(foreign, @ozon_sku, 500, supply_id: supply[:id])

    payload = run_query(min_units: 1)

    assert_equal 10, payload[:unit_count]
    assert_equal 10.to_d, payload[:average_rub]
  end

  test "ignores refunds that net a supply to nothing and fee lines outside the window" do
    supply = create_supply(10, accrued: Date.new(2026, 9, 1))
    fee_lines(supply, [-100, 100], Date.new(2026, 9, 1))
    other = create_supply(10, accrued: Date.new(2026, 10, 25))
    fee_lines(other, [-900], Date.new(2026, 10, 25))

    payload = run_query(min_units: 1)

    assert_equal 0, payload[:sample_count]
    assert_nil payload[:average_rub]
  end

  test "an SKU without Ozon bindings has nothing" do
    sku = Ec::Sku.create!(sku_code: "ACT-XD-NONE-#{@token}")

    payload = Ec::SkuActualCrossDockQuery.run(sku: sku, today: TODAY)

    assert_equal 0, payload[:sample_count]
    assert_nil payload[:average_rub]
    assert_equal 0.to_d, payload[:total_rub]
  ensure
    Ec::OperationLog.where(record_type: "Ec::Sku", record_id: sku.id).delete_all
    Ec::Sku.with_deleted.where(id: sku.id).delete_all
  end

  private

  def run_query(min_units:)
    Ec::SkuActualCrossDockQuery.run(sku: @sku, today: TODAY, min_units: min_units)
  end

  # A supply with `quantity` units of the SKU; `accrued` is only recorded for the test's own bookkeeping.
  def create_supply(quantity, accrued:, crossdock: true, created_at: Time.utc(2026, 9, 1), order_status: "COMPLETED")
    @supply_counter = (@supply_counter || 0) + 1
    number = @supply_number + @supply_counter
    order = RawOzon::SupplyOrder.create!(
      account_id: @account.id, supply_order_id: "S#{@token}#{@supply_counter}", status: order_status, raw_json: {}, created_at: created_at
    )
    create_item(order, @ozon_sku, quantity, supply_id: number, crossdock: crossdock)
    { order: order, id: number, accrued: accrued }
  end

  def create_item(order, platform_sku_id, quantity, supply_id:, crossdock: true)
    RawOzon::SupplyOrderItem.create!(
      supply_order_id: order.id, ozon_supply_id: supply_id, platform_sku_id: platform_sku_id,
      bundle_id: SecureRandom.uuid, quantity: quantity, is_crossdock: crossdock, state: "COMPLETED"
    )
  end

  def fee_lines(supply, amounts, date)
    amounts.each { |amount| accrual(supply[:id], amount, date) }
  end

  def accrual(supply_number, amount, date)
    RawOzon::AccrualByDay.create!(
      account_id: @account.id, accrual_date: date, accrued_category: "NON_ITEM", amount: amount, currency_code: "RUB",
      ozon_sku_id: @ozon_sku, posting_number: supply_number&.to_s, unit_number: supply_number&.to_s,
      synced_at: Time.current, type_id: Ec::SkuActualCrossDockQuery::CROSSDOCK_TYPE_ID
    )
  end
end
