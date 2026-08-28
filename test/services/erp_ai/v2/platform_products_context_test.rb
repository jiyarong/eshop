require "test_helper"

class ErpAI::V2::PlatformProductsContextTest < ActiveSupport::TestCase
  def setup
    @token = SecureRandom.hex(6)
    @sku = Ec::Sku.create!(sku_code: "CTX-PRICE-#{@token}")
    @wb_account = RawWb::SellerAccount.create!(name: "WB #{@token}", api_token: @token, company_type: "small")
    @ozon_account = RawOzon::SellerAccount.create!(company_name: "Ozon #{@token}", client_id: @token, api_key: @token, company_type: "small")
    @wb_store = Ec::Store.create!(platform: "wb", store_name: "WB #{@token}", company_type: "small", wb_raw_account_id: @wb_account.id)
    @ozon_store = Ec::Store.create!(platform: "ozon", store_name: "Ozon #{@token}", company_type: "small", ozon_raw_account_id: @ozon_account.id)
  end

  def teardown
    RawWb::ProductPrice.where(account_id: @wb_account&.id).delete_all
    RawOzon::ProductPrice.where(account_id: @ozon_account&.id).delete_all
    RawWb::Product.where(account_id: @wb_account&.id).delete_all
    RawOzon::Product.where(account_id: @ozon_account&.id).delete_all
    Ec::SkuProduct.where(sku_code: @sku&.sku_code).delete_all
    Ec::Store.where(id: [@wb_store&.id, @ozon_store&.id]).delete_all
    Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
    RawWb::SellerAccount.where(id: @wb_account&.id).delete_all
    RawOzon::SellerAccount.where(id: @ozon_account&.id).delete_all
  end

  test "returns WB and Ozon product basics with current prices" do
    wb_product = RawWb::Product.create!(
      account: @wb_account, nm_id: 910_000_001, vendor_code: "WB-#{@token}", title: "金色毛巾架",
      brand: "辕隆", subject_name: "毛巾架", wb_category: "卫浴", description: "商品描述",
      synced_at: Time.zone.parse("2026-08-20 10:00:00")
    )
    RawWb::ProductPrice.create!(
      account: @wb_account, product: wb_product, price: 100, discount: 15, club_discount: 3,
      final_price: 85, is_in_quarantine: false
    )
    ozon_product = RawOzon::Product.create!(
      account: @ozon_account, ozon_product_id: 920_000_001, offer_id: "OZ-#{@token}", name: "金色毛巾架",
      description_category_id: 456, type_id: 789, currency_code: "RUB", barcodes: ["123456"],
      images: [{ "file_name" => "excluded" }], commissions: [{ "value" => 10 }], raw_json: { secret: "excluded" },
      synced_at: Time.zone.parse("2026-08-20 11:00:00")
    )
    RawOzon::ProductPrice.create!(
      account: @ozon_account, ozon_product_id: ozon_product.ozon_product_id, offer_id: ozon_product.offer_id,
      price: 200, old_price: 250, marketing_price: 190, min_price: 180, buybox_price: 188,
      discount_percent: 24, is_in_discount: true, currency_code: "RUB", acquiring: 2.5,
      volume_weight: 1.25, commissions: [{ "value" => 20 }], raw_json: { secret: "excluded" }
    )
    bindings = [
      Ec::SkuProduct.create!(sku: @sku, store: @wb_store, platform: "wb", product_id: wb_product.nm_id.to_s, offer_id: wb_product.vendor_code),
      Ec::SkuProduct.create!(sku: @sku, store: @ozon_store, platform: "ozon", product_id: ozon_product.ozon_product_id.to_s, offer_id: ozon_product.offer_id)
    ]

    result = ErpAI::V2::PlatformProductsContext.new(sku_products: bindings).call

    assert_equal "金色毛巾架", result[0].dig(:product_info, "title")
    assert_equal BigDecimal("85"), result[0].dig(:price_info, "final_price")
    assert_equal "金色毛巾架", result[1].dig(:product_info, "name")
    assert_equal BigDecimal("190"), result[1].dig(:price_info, "marketing_price")
    refute_includes result[1][:product_info], "raw_json"
    refute_includes result[1][:product_info], "images"
    refute_includes result[1][:price_info], "commissions"
  end

  test "returns nil product and price information when raw product is missing" do
    binding = Ec::SkuProduct.create!(
      sku: @sku, store: @ozon_store, platform: "ozon", product_id: "999999999", offer_id: "MISSING-#{@token}"
    )

    result = ErpAI::V2::PlatformProductsContext.new(sku_products: [binding]).call.first

    assert_nil result[:product_info]
    assert_nil result[:price_info]
  end
end
