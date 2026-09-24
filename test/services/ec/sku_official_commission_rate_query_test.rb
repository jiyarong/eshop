require "test_helper"

class Ec::SkuOfficialCommissionRateQueryTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(6)
    @sku = Ec::Sku.create!(sku_code: "COMMISSION-#{@token.upcase}", product_name: "Commission query", is_active: true)
    @records = Hash.new { |hash, key| hash[key] = [] }
  end

  teardown do
    Ec::OperationLog.where(record_type: "Ec::SkuProduct", record_id: @records[:sku_products]).delete_all
    Ec::OperationLog.where(record_type: "Ec::Store", record_id: @records[:stores]).delete_all
    Ec::SkuProduct.where(id: @records[:sku_products]).delete_all
    RawOzon::ProductPrice.where(id: @records[:ozon_prices]).delete_all
    RawWb::Product.where(id: @records[:wb_products]).delete_all
    RawWb::Subject.where(id: @records[:wb_subjects]).delete_all
    RawWb::Category.where(id: @records[:wb_categories]).delete_all
    Ec::Store.where(id: @records[:stores]).delete_all
    RawOzon::SellerAccount.where(id: @records[:ozon_accounts]).delete_all
    RawWb::SellerAccount.where(id: @records[:wb_accounts]).delete_all
    Ec::OperationLog.where(record_type: "Ec::Sku", record_id: @sku.id).delete_all
    Ec::Sku.where(id: @sku.id).delete_all
  end

  test "resolves Ozon bindings by store account and product id and groups equal rates" do
    account = track(:ozon_accounts, RawOzon::SellerAccount.create!(
      client_id: "commission-#{@token}", api_key: "key-#{@token}", company_type: "general"
    ))
    store = track(:stores, Ec::Store.create!(
      platform: "ozon", store_name: "Ozon commission #{@token}", company_type: "general",
      ozon_raw_account_id: account.id
    ))
    product_ids = [ 91_000_001, 91_000_002 ]
    product_ids.each do |product_id|
      track(:sku_products, Ec::SkuProduct.create!(sku: @sku, store:, product_id: product_id.to_s))
      track(:ozon_prices, RawOzon::ProductPrice.create!(
        account:, ozon_product_id: product_id, commissions: { "sales_percent_fbo" => 17.5 },
        raw_json: {}, synced_at: Time.zone.parse("2026-09-21 08:30")
      ))
    end

    payload = Ec::SkuOfficialCommissionRateQuery.run(sku: @sku, platform: "ozon", delivery_mode: "fbo")

    assert_equal 2, payload.fetch(:binding_count)
    assert_equal 2, payload.fetch(:resolved_count)
    assert_equal "sales_percent_fbo", payload.dig(:source, :field)
    assert_equal "0.175", payload.fetch(:rates).sole.fetch(:rate)
    assert_equal 2, payload.fetch(:rates).sole.fetch(:product_count)
  end

  test "resolves WB binding through raw product subject and the shared tariff snapshot" do
    account = track(:wb_accounts, RawWb::SellerAccount.create!(
      name: "wb-commission-#{@token}", api_token: "token-#{@token}", company_type: "small"
    ))
    store = track(:stores, Ec::Store.create!(
      platform: "wb", store_name: "WB commission #{@token}", company_type: "small",
      wb_raw_account_id: account.id
    ))
    category = track(:wb_categories, RawWb::Category.create!(
      wb_id: unique_number(10), name: "category-#{@token}"
    ))
    subject = track(:wb_subjects, RawWb::Subject.create!(
      wb_id: unique_number(20), name: "subject-#{@token}", category:
    ))
    product = track(:wb_products, RawWb::Product.create!(
      account:, nm_id: unique_number(30), vendor_code: "vendor-#{@token}", subject:
    ))
    track(:sku_products, Ec::SkuProduct.create!(sku: @sku, store:, product_id: product.nm_id.to_s))

    calls = []
    resolver = Object.new
    resolver.define_singleton_method(:rate_for_wb_product) do |product:, delivery_mode:|
      calls << [ product, delivery_mode ]
      BigDecimal("0.175")
    end
    payload = Ec::SkuOfficialCommissionRateQuery.new(
      sku: @sku, platform: "wb", delivery_mode: "fbo", wb_resolver: resolver
    ).run

    assert_equal [ [ product, "fbo" ] ], calls
    assert_equal "paid_storage_kgvp", payload.dig(:source, :field)
    assert_equal "0.175", payload.fetch(:rates).sole.fetch(:rate)
    assert_equal 1, payload.fetch(:resolved_count)
  end

  private

  def track(type, record)
    @records[type] << record.id
    record
  end

  def unique_number(offset)
    700_000_000 + (@token.hex % 100_000_000) + offset
  end
end
