require "test_helper"
require "stringio"

SCRIPT_PATH = Rails.root.join("script/reallocate_ozon_crossdock_fees_by_volume.rb")
source = SCRIPT_PATH.read.sub(/\nOzonCrossdockVolumeReallocator\.new\.call\s*\z/, "")
eval(source, TOPLEVEL_BINDING, SCRIPT_PATH.to_s) unless defined?(OzonCrossdockVolumeReallocator)

class ReallocateOzonCrossdockFeesByVolumeTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(5)
    @date = Date.new(2026, 7, 21)
    @account = RawOzon::SellerAccount.create!(client_id: "reallocate-#{@token}", api_key: "test", company_name: "Reallocate #{@token}", company_type: "general")
    @store = Ec::Store.create!(platform: "ozon", store_name: "Reallocate #{@token}", company_type: "general", ozon_raw_account_id: @account.id)
    create_sku("3001", "RA#{@token}A", quantity: 2, dimensions: [10, 10, 10])
    create_sku("3002", "RA#{@token}B", quantity: 1, dimensions: [20, 10, 10])
    @supply = RawOzon::SupplyOrder.create!(account: @account, supply_order_id: "ORDER-#{@token}", status: "COMPLETED", items: { "3001" => 2, "3002" => 1 }, raw_json: { "supplies" => [{ "supply_id" => "SUPPLY-#{@token}" }] }, synced_at: Time.current)
    create_fee("3001", -7.50)
    create_fee("3002", -2.51)
  end

  teardown do
    RawOzon::AccrualByDay.where(account_id: @account&.id).delete_all
    RawOzon::SupplyOrder.where(account_id: @account&.id).delete_all
    Ec::SkuDimension.where(sku_code: @sku_codes).delete_all
    Ec::SkuProduct.where(store_id: @store&.id).delete_all
    Ec::Sku.with_deleted.where(sku_code: @sku_codes).delete_all
    Ec::Store.where(id: @store&.id).delete_all
    RawOzon::SellerAccount.where(id: @account&.id).delete_all
  end

  test "previews without changing rows" do
    before = fee_amounts
    output = run_script

    assert_equal before, fee_amounts
    assert_includes output, "DRY RUN"
    assert_includes output, "total=-10.01"
  end

  test "reallocates by total inner volume and preserves the supply total" do
    run_script("APPLY" => "1")

    assert_equal({ 3001 => BigDecimal("-5.01"), 3002 => BigDecimal("-5.00") }, fee_amounts)
    assert_equal BigDecimal("-10.01"), fee_amounts.values.sum
  end

  private

  def create_sku(platform_sku_id, sku_code, quantity:, dimensions:)
    sku_code = sku_code.upcase
    @sku_codes ||= []
    @sku_codes << sku_code
    Ec::Sku.create!(sku_code: sku_code)
    Ec::SkuProduct.create!(store: @store, platform: "ozon", sku_code: sku_code, platform_sku_id: platform_sku_id, product_id: "P#{platform_sku_id}")
    Ec::SkuDimension.insert_all!([{
      sku_code: sku_code,
      inner_length_cm: dimensions[0],
      inner_width_cm: dimensions[1],
      inner_height_cm: dimensions[2],
      created_at: Time.current,
      updated_at: Time.current
    }])
  end

  def create_fee(ozon_sku_id, amount)
    RawOzon::AccrualByDay.create!(account: @account, accrual_date: @date, accrued_category: "NON_ITEM", type_id: 12, amount: amount, currency_code: "RUB", ozon_sku_id: ozon_sku_id, posting_number: "SUPPLY-#{@token}", unit_number: "SUPPLY-#{@token}", synced_at: Time.current)
  end

  def fee_amounts
    RawOzon::AccrualByDay.where(account_id: @account.id, type_id: 12).pluck(:ozon_sku_id, :amount).to_h
  end

  def run_script(overrides = {})
    env = { "ACCOUNT_ID" => @account.id.to_s, "FROM_DATE" => @date.iso8601, "TO_DATE" => @date.iso8601 }.merge(overrides)
    stdout = StringIO.new
    OzonCrossdockVolumeReallocator.new(env: env, stdout: stdout).call
    stdout.string
  end
end
