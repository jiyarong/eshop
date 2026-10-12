require "test_helper"
require "securerandom"

class Ec::OrderImport::WbStatsOnlyBackfillTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(4).upcase
    @account = RawWb::SellerAccount.create!(name: "wb-backfill-#{@token}", api_token: "t-#{@token}", company_type: "small")
    @store = Ec::Store.create!(
      platform: "wb", store_name: "WB Backfill #{@token}", company_type: "small",
      wb_raw_account_id: @account.id, is_active: true
    )
    @sku = Ec::Sku.create!(sku_code: "BACKFILL-#{@token}", product_name: "Backfill")
    @product = Ec::SkuProduct.create!(sku_code: @sku.sku_code, store: @store, product_id: "777#{@token.to_i(16) % 10_000}")
  end

  teardown do
    product_ids = Ec::SkuProduct.where(sku_code: @sku.sku_code).pluck(:id)
    order_ids = Ec::Order.where(store_id: @store.id).select(:id)
    Ec::OrderSourceLink.where(order_id: order_ids).delete_all
    Ec::OrderItem.where(store_id: @store.id).delete_all
    Ec::OrderFulfillment.where(store_id: @store.id).delete_all
    Ec::Order.where(store_id: @store.id).delete_all
    RawWb::StatsOrder.where(account_id: @account.id).delete_all
    RawWb::Order.where(account_id: @account.id).delete_all
    Ec::OperationAction.where(ec_sku_id: @sku.id).delete_all
    Ec::SkuProduct.where(sku_code: @sku.sku_code).delete_all
    Ec::Store.where(id: @store.id).delete_all
    RawWb::SellerAccount.where(id: @account.id).delete_all
    Ec::Sku.with_deleted.where(id: @sku.id).delete_all
    {
      "Ec::SkuProduct" => product_ids, "Ec::Store" => [ @store.id ], "Ec::Sku" => [ @sku.id ]
    }.each do |record_type, ids|
      Ec::OperationLog.where(record_type: record_type, record_id: ids).delete_all
    end
  end

  test "imports unlinked statistics orders that have no marketplace order and leaves covered ones alone" do
    stats_only = create_stats_order("ONLY-#{@token}", "Склад WB")
    covered = create_stats_order("COVERED-#{@token}", "Склад продавца")
    RawWb::Order.create!(
      account: @account, wb_order_id: 60_000_000_000 + @token.to_i(16), srid: covered.srid,
      nm_id: @product.product_id.to_i, delivery_type: "fbs", wb_status: "sold", supplier_status: "complete"
    )

    importer = Ec::OrderImport::Wb.new

    assert_equal 1, importer.import_unlinked_stats_only_orders(dry_run: true)
    assert_equal 0, Ec::Order.where(store_id: @store.id).count

    assert_equal 1, importer.import_unlinked_stats_only_orders
    order = Ec::Order.find_by!(store_id: @store.id)
    assert_equal stats_only.srid, order.external_order_id
    assert_equal "fbw", order.fulfillments.sole.fulfillment_type
    assert_equal 0, importer.import_unlinked_stats_only_orders
  end

  def create_stats_order(srid, warehouse_type)
    RawWb::StatsOrder.create!(
      account: @account, srid: srid, nm_id: @product.product_id.to_i, order_date: Time.zone.parse("2026-05-10 10:00:00"),
      warehouse_type: warehouse_type, warehouse_name: "Склад WB РФ", is_cancel: false,
      supplier_article: @sku.sku_code, synced_at: Time.zone.parse("2026-05-10 10:05:00")
    )
  end
end
