require "test_helper"

module Ec
  class UnboundRawProductReportTest < ActiveSupport::TestCase
    setup do
      @token = SecureRandom.hex(4).upcase
      @sku = Ec::Sku.create!(sku_code: "BOUND-#{@token}", product_name: "已绑定 SKU")
      @ozon_account = RawOzon::SellerAccount.create!(
        company_name: "Unbound Report Ozon #{@token}",
        client_id: "unbound-report-ozon-#{@token}",
        api_key: "api-key-#{@token}",
        company_type: "general"
      )
      @wb_account = RawWb::SellerAccount.create!(
        name: "Unbound Report WB #{@token}",
        api_token: "unbound-report-wb-#{@token}",
        company_type: "small"
      )
      @ozon_store = Ec::Store.create!(
        platform: "ozon",
        store_name: "Unbound Report Ozon Store #{@token}",
        company_type: "general",
        ozon_raw_account_id: @ozon_account.id
      )
      @wb_store = Ec::Store.create!(
        platform: "wb",
        store_name: "Unbound Report WB Store #{@token}",
        company_type: "small",
        wb_raw_account_id: @wb_account.id
      )
      @bound_ozon_product = create_ozon_product!("91#{@token.hex % 1_000_000}", "BOUND-OZON-#{@token}", "已绑定 Ozon 商品")
      @unbound_ozon_product = create_ozon_product!("92#{@token.hex % 1_000_000}", "UNBOUND-OZON-#{@token}", "未绑定 Ozon 商品")
      @bound_wb_product = create_wb_product!("81#{@token.hex % 1_000_000}", "BOUND-WB-#{@token}", "已绑定 WB 商品")
      @unbound_wb_product = create_wb_product!("82#{@token.hex % 1_000_000}", "UNBOUND-WB-#{@token}", "未绑定 WB 商品")

      Ec::SkuProduct.create!(sku_code: @sku.sku_code, store: @ozon_store, product_id: @bound_ozon_product.ozon_product_id.to_s)
      Ec::SkuProduct.create!(sku_code: @sku.sku_code, store: @wb_store, product_id: @bound_wb_product.nm_id.to_s)
    end

    teardown do
      Ec::SkuProduct.where(sku_code: @sku&.sku_code).delete_all if defined?(Ec::SkuProduct)
      RawOzon::Product.where(account_id: @ozon_account&.id).delete_all if @ozon_account
      RawWb::Product.where(account_id: @wb_account&.id).delete_all if @wb_account
      @ozon_store&.destroy
      @wb_store&.destroy
      @ozon_account&.destroy
      @wb_account&.destroy
      Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
    end

    test "returns raw ozon and wb products without sku product bindings" do
      rows = Ec::UnboundRawProductReport.call.select { |row| row.store_name.to_s.include?(@token) }

      assert_equal 2, rows.size
      assert_equal ["ozon", "wb"], rows.map(&:platform).sort
      assert_includes rows.map(&:product_id).map(&:to_s), @unbound_ozon_product.ozon_product_id.to_s
      assert_includes rows.map(&:product_id).map(&:to_s), @unbound_wb_product.nm_id.to_s
      refute_includes rows.map(&:product_id).map(&:to_s), @bound_ozon_product.ozon_product_id.to_s
      refute_includes rows.map(&:product_id).map(&:to_s), @bound_wb_product.nm_id.to_s
    end

    test "filters unbound raw products by store" do
      rows = Ec::UnboundRawProductReport.call(store_id: @ozon_store.id)

      assert_equal [@ozon_store.id], rows.map(&:store_id).uniq
      assert_equal [@unbound_ozon_product.ozon_product_id.to_s], rows.map(&:product_id).map(&:to_s)
    end

    private

    def create_ozon_product!(product_id, offer_id, name)
      RawOzon::Product.create!(
        account: @ozon_account,
        ozon_product_id: product_id,
        offer_id: offer_id,
        name: name,
        raw_json: { "sku" => "PLATFORM-#{offer_id}" },
        synced_at: Time.zone.parse("2026-06-15 10:00:00")
      )
    end

    def create_wb_product!(nm_id, vendor_code, title)
      RawWb::Product.create!(
        account: @wb_account,
        nm_id: nm_id,
        vendor_code: vendor_code,
        title: title,
        synced_at: Time.zone.parse("2026-06-15 10:00:00")
      )
    end
  end
end
