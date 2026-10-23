require "test_helper"

class Ec::SkuOfficialCommissionRateTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(6)
    @sku = Ec::Sku.create!(sku_code: "OFFRATE-#{@token.upcase}", product_name: "Official rate", is_active: true)
    @records = Hash.new { |hash, key| hash[key] = [] }
    @account = track(:ozon_accounts, RawOzon::SellerAccount.create!(
      client_id: "offrate-#{@token}", api_key: "key-#{@token}", company_type: "general"
    ))
    @store = track(:stores, Ec::Store.create!(
      platform: "ozon", store_name: "Ozon offrate #{@token}", company_type: "general", ozon_raw_account_id: @account.id
    ))
  end

  teardown do
    Ec::OperationLog.where(record_type: "Ec::SkuProduct", record_id: @records[:sku_products]).delete_all
    Ec::OperationLog.where(record_type: "Ec::Store", record_id: @records[:stores]).delete_all
    Ec::SkuProduct.where(id: @records[:sku_products]).delete_all
    RawOzon::ProductPrice.where(id: @records[:ozon_prices]).delete_all
    Ec::Store.where(id: @records[:stores]).delete_all
    RawOzon::SellerAccount.where(id: @records[:ozon_accounts]).delete_all
    Ec::OperationLog.where(record_type: "Ec::Sku", record_id: @sku.id).delete_all
    Ec::Sku.where(id: @sku.id).delete_all
  end

  test "gives the rate when every listing resolves to the same official rate" do
    bind_listing(91_100_001, "sales_percent_fbo" => 17.5)
    bind_listing(91_100_002, "sales_percent_fbo" => 17.5)

    result = Ec::SkuOfficialCommissionRate.call(sku: @sku, platform: "ozon", delivery_mode: "fbo")

    assert_equal BigDecimal("0.175"), result[:rate]
    assert_nil result[:reason]
  end

  test "gives no rate when listings have different rates" do
    bind_listing(91_100_003, "sales_percent_fbo" => 17.5)
    bind_listing(91_100_004, "sales_percent_fbo" => 21)

    result = Ec::SkuOfficialCommissionRate.call(sku: @sku, platform: "ozon", delivery_mode: "fbo")

    assert_nil result[:rate]
    assert_equal "rates_differ", result[:reason]
  end

  test "gives no rate when one listing has no tariff for the mode" do
    bind_listing(91_100_005, "sales_percent_fbo" => 17.5)
    bind_listing(91_100_006, "sales_percent_fbs" => 19)

    result = Ec::SkuOfficialCommissionRate.call(sku: @sku, platform: "ozon", delivery_mode: "fbo")

    assert_nil result[:rate]
    assert_equal "unresolved_listings", result[:reason]
  end

  test "gives no rate when the SKU has no listing on the platform" do
    result = Ec::SkuOfficialCommissionRate.call(sku: @sku, platform: "wb", delivery_mode: "fbs")

    assert_nil result[:rate]
    assert_equal "no_listings", result[:reason]
  end

  private

  def bind_listing(product_id, commissions)
    track(:sku_products, Ec::SkuProduct.create!(sku: @sku, store: @store, product_id: product_id.to_s))
    track(:ozon_prices, RawOzon::ProductPrice.create!(
      account: @account, ozon_product_id: product_id, commissions: commissions,
      raw_json: {}, synced_at: Time.zone.parse("2026-09-21 08:30")
    ))
  end

  def track(type, record)
    @records[type] << record.id
    record
  end
end
