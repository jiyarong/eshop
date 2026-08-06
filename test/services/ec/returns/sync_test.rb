require "test_helper"

module Ec
  module Returns
    class SyncTest < ActiveSupport::TestCase
      setup do
        @token = SecureRandom.hex(6).upcase
        @number = @token.to_i(16)
        create_ozon_records
        create_wb_records
      end

      teardown do
        Ec::ReturnSourceLink.where(source_type: [ "RawOzon::Return", "RawWb::GoodsReturn" ])
          .where(source_id: [ @ozon_return&.id, @wb_return&.id ].compact).delete_all
        Ec::ReturnItem.where(return_id: Ec::Return.where(store_id: [ @ozon_store&.id, @wb_store&.id ]).select(:id)).delete_all
        Ec::Return.where(store_id: [ @ozon_store&.id, @wb_store&.id ]).delete_all
        RawOzon::Return.where(id: @ozon_return&.id).delete_all
        RawWb::GoodsReturn.where(id: @wb_return&.id).delete_all
        Ec::OrderSourceLink.where(order_id: [ @ozon_order&.id, @wb_order&.id ].compact).delete_all
        Ec::OrderItem.where(order_id: [ @ozon_order&.id, @wb_order&.id ]).delete_all
        Ec::Order.where(id: [ @ozon_order&.id, @wb_order&.id ].compact).delete_all
        Ec::SkuProduct.where(id: [ @ozon_sku_product&.id, @wb_sku_product&.id ].compact).delete_all
        Ec::Sku.with_deleted.where(id: [ @ozon_sku&.id, @wb_sku&.id ].compact).delete_all
        Ec::Store.where(id: [ @ozon_store&.id, @wb_store&.id ].compact).delete_all
        RawOzon::SellerAccount.where(id: @ozon_account&.id).delete_all
        RawWb::SellerAccount.where(id: @wb_account&.id).delete_all
      end

      test "normalizes Ozon return with hard order and SKU bindings" do
        result = Ec::Returns::Sync.call(raw_records: [ @ozon_return ])
        normalized = Ec::Return.find_by!(store: @ozon_store, return_key: @ozon_return.return_id.to_s)
        item = normalized.items.sole

        assert_equal({ normalized: 1, missing_order: 0, missing_sku_product: 0 }, result)
        assert_equal @ozon_order, normalized.order
        assert_equal "at_platform", normalized.process_status
        assert_equal "platform_return_warehouse", normalized.inventory_location
        assert_equal "unknown", normalized.inventory_condition
        assert_equal @ozon_sku_product, item.sku_product
        assert_equal @ozon_order_item, item.order_item
        assert_not item.restockable
        assert_equal @ozon_return, normalized.source_links.sole.source
      end

      test "normalizes WB pickup state and cancellation return" do
        result = Ec::Returns::Sync.call(raw_records: [ @wb_return ])
        normalized = Ec::Return.find_by!(store: @wb_store, return_key: @wb_return.shk_id.to_s)
        item = normalized.items.sole

        assert_equal({ normalized: 1, missing_order: 0, missing_sku_product: 0 }, result)
        assert_equal "cancellation_return", normalized.return_type
        assert_equal "ready_for_seller_pickup", normalized.process_status
        assert_equal "platform_return_warehouse", normalized.inventory_location
        assert_equal @wb_sku_product, item.sku_product
        assert_equal @wb_order_item, item.order_item
      end

      test "finds WB order through a primary source link scoped to the same store" do
        other_account = RawWb::SellerAccount.create!(name: "Other WB #{@token}", api_token: "other-#{@token}", company_type: "small")
        other_store = Ec::Store.create!(platform: "wb", store_name: "Other WB #{@token}",
          company_type: "small", wb_raw_account_id: other_account.id)
        other_order = Ec::Order.create!(platform: "wb", store: other_store, order_key: "OTHER-WB-#{@token}")
        other_link = Ec::OrderSourceLink.create!(order: other_order, platform: "wb", source_role: "primary",
          source_type: "RawWb::Order", source_id: @number + 24, source_key: @wb_return.order_id.to_s)

        normalized = Ec::Returns::Sync.call(raw_records: [ @wb_return ])
        ec_return = Ec::Return.find_by!(store: @wb_store, return_key: @wb_return.shk_id.to_s)

        assert_equal 0, normalized[:missing_order]
        assert_equal @wb_order, ec_return.order
      ensure
        other_link&.delete
        other_order&.delete
        other_store&.delete
        other_account&.delete
      end

      test "repeated sync is idempotent and preserves restockable" do
        Ec::Returns::Sync.call(raw_records: [ @ozon_return ])
        normalized = Ec::Return.find_by!(store: @ozon_store, return_key: @ozon_return.return_id.to_s)
        normalized.items.sole.update!(restockable: true)

        @ozon_return.update!(raw_json: { "visual" => { "status" => "MovingToSeller" } })
        Ec::Returns::Sync.call(raw_records: RawOzon::Return.where(id: @ozon_return.id))

        assert_equal 1, Ec::Return.where(store: @ozon_store, return_key: @ozon_return.return_id.to_s).count
        assert_equal 1, normalized.items.reload.count
        assert normalized.items.sole.restockable
        assert_equal "moving_to_seller", normalized.reload.process_status
      end

      test "reports missing hard bindings without using offer id as fallback" do
        @ozon_return.update!(ozon_sku: @number + 99, offer_id: @ozon_sku_product.offer_id,
          posting_number: "MISSING-#{@token}", order_number: nil, order_id: nil)

        result = Ec::Returns::Sync.call(raw_records: [ @ozon_return ])

        assert_equal({ normalized: 1, missing_order: 1, missing_sku_product: 1 }, result)
        assert_nil Ec::Return.find_by!(store: @ozon_store, return_key: @ozon_return.return_id.to_s).items.sole.sku_product
      end

      private

      def create_ozon_records
        @ozon_account = RawOzon::SellerAccount.create!(client_id: "return-#{@token}", api_key: "key",
          company_type: "general", raw_json: {})
        @ozon_store = Ec::Store.create!(platform: "ozon", store_name: "Ozon #{@token}",
          company_type: "general", ozon_raw_account_id: @ozon_account.id)
        @ozon_sku = Ec::Sku.create!(sku_code: "RET-OZ-#{@token}")
        @ozon_sku_product = Ec::SkuProduct.create!(sku: @ozon_sku, store: @ozon_store,
          product_id: (@number + 10).to_s, platform_sku_id: (@number + 11).to_s, offer_id: "OFFER-#{@token}")
        @ozon_order = Ec::Order.create!(platform: "ozon", store: @ozon_store, order_key: "OZ-#{@token}",
          order_status: "delivered", external_order_id: (@number + 12).to_s,
          external_order_number: "POSTING-#{@token}")
        @ozon_order_item = @ozon_order.items.create!(platform: "ozon", store: @ozon_store,
          platform_sku_id: @ozon_sku_product.platform_sku_id, quantity: 2)
        @ozon_return = RawOzon::Return.create!(account: @ozon_account, return_id: @number + 13,
          return_schema: "FBO", return_type: "Return", order_id: @ozon_order.external_order_id,
          posting_number: @ozon_order.external_order_number, ozon_sku: @ozon_sku_product.platform_sku_id,
          offer_id: @ozon_sku_product.offer_id, quantity: 2, visual_status: "stale-status",
          raw_json: { "visual" => { "status" => { "sys_name" => "ReturnedToOzon" } } }, synced_at: Time.current)
      end

      def create_wb_records
        @wb_account = RawWb::SellerAccount.create!(name: "WB #{@token}", api_token: "token-#{@token}", company_type: "small")
        @wb_store = Ec::Store.create!(platform: "wb", store_name: "WB #{@token}",
          company_type: "small", wb_raw_account_id: @wb_account.id)
        @wb_sku = Ec::Sku.create!(sku_code: "RET-WB-#{@token}")
        @wb_sku_product = Ec::SkuProduct.create!(sku: @wb_sku, store: @wb_store,
          product_id: (@number + 20).to_s, offer_id: "WB-OFFER-#{@token}")
        @wb_order = Ec::Order.create!(platform: "wb", store: @wb_store, order_key: "WB-#{@token}",
          order_status: "cancelled", external_order_id: "UNRELATED-#{@token}",
          external_order_number: "SRID-#{@token}")
        @wb_order_item = @wb_order.items.create!(platform: "wb", store: @wb_store,
          platform_sku_id: @wb_sku_product.product_id, quantity: 1)
        @wb_return = RawWb::GoodsReturn.create!(account: @wb_account, shk_id: @number + 22,
          order_id: @number + 21, srid: "RETURN-SRID-#{@token}.r",
          nm_id: @wb_sku_product.product_id, status: "Готов к выдаче",
          ready_to_return_dt: Time.current, synced_at: Time.current)
        Ec::OrderSourceLink.create!(order: @wb_order, platform: "wb", source_role: "primary",
          source_type: "RawWb::Order", source_id: @number + 23, source_key: @wb_return.order_id.to_s)
      end
    end
  end
end
