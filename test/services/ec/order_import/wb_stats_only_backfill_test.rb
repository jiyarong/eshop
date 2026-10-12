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
    account_ids = [ @account.id, @other_account&.id ].compact
    RawWb::StatsOrder.where(account_id: account_ids).delete_all
    RawWb::Order.where(account_id: account_ids).delete_all
    Ec::OperationAction.where(ec_sku_id: @sku.id).delete_all
    Ec::SkuProduct.where(sku_code: @sku.sku_code).delete_all
    Ec::Store.where(id: @store.id).delete_all
    RawWb::SellerAccount.where(id: account_ids).delete_all
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
    assert_equal 1, Ec::Order.where(store_id: @store.id).count
    order = Ec::Order.find_by!(store_id: @store.id)
    assert_equal stats_only.srid, order.external_order_id
    assert_equal "fbw", order.fulfillments.sole.fulfillment_type
    assert_not Ec::OrderSourceLink.exists?(source_type: "RawWb::StatsOrder", source_id: covered.id)
    assert Ec::OrderSourceLink.exists?(source_type: "RawWb::StatsOrder", source_id: stats_only.id)
    assert_equal 0, importer.import_unlinked_stats_only_orders
    assert_equal 1, Ec::Order.where(store_id: @store.id).count
  end

  test "skips a statistics order whose srid differs but whose g_number matches a marketplace order" do
    stats = create_stats_order("DIFFSRID-#{@token}", "Склад WB", g_number: "G#{@token}")
    create_marketplace_order(srid: "OTHERSRID-#{@token}", g_number: "G#{@token}")

    importer = Ec::OrderImport::Wb.new

    assert_equal 0, importer.import_unlinked_stats_only_orders(dry_run: true)
    assert_equal 1, importer.count_unlinked_stats_covered_only_by_g_number
    assert_equal 0, importer.import_unlinked_stats_only_orders
    assert_equal 0, Ec::Order.where(store_id: @store.id).count
    assert_not Ec::OrderSourceLink.exists?(source_type: "RawWb::StatsOrder", source_id: stats.id)
  end

  test "skips a synthetic nosrid statistics order whose g_number matches a marketplace order" do
    srid = "nosrid:#{@account.id}:G#{@token}:#{@product.product_id}:1"
    create_stats_order(srid, "Склад WB", g_number: "G#{@token}")
    create_marketplace_order(srid: "REALSRID-#{@token}", g_number: "G#{@token}")

    importer = Ec::OrderImport::Wb.new

    assert_equal 0, importer.import_unlinked_stats_only_orders(dry_run: true)
    assert_equal 1, importer.count_unlinked_stats_covered_only_by_g_number
    assert_equal 0, importer.import_unlinked_stats_only_orders
    assert_equal 0, Ec::Order.where(store_id: @store.id).count
  end

  test "imports a statistics order whose g_number is blank or unmatched" do
    create_stats_order("BLANKG-#{@token}", "Склад WB", g_number: "")
    create_stats_order("UNMATCHED-#{@token}", "Склад WB", g_number: "G-UNMATCHED-#{@token}")
    create_marketplace_order(srid: "REALSRID-#{@token}", g_number: "G#{@token}")
    create_marketplace_order(srid: "BLANKRAW-#{@token}", g_number: "")

    importer = Ec::OrderImport::Wb.new

    assert_equal 2, importer.import_unlinked_stats_only_orders(dry_run: true)
    assert_equal 0, importer.count_unlinked_stats_covered_only_by_g_number
    assert_equal 2, importer.import_unlinked_stats_only_orders
  end

  test "does not count statistics orders of an account without a WB store" do
    @other_account = RawWb::SellerAccount.create!(
      name: "wb-nostore-#{@token}", api_token: "n-#{@token}", company_type: "small"
    )
    RawWb::StatsOrder.create!(
      account: @other_account, srid: "NOSTORE-#{@token}", nm_id: @product.product_id.to_i,
      order_date: Time.zone.parse("2026-05-10 10:00:00"), warehouse_type: "Склад WB", is_cancel: false
    )
    create_stats_order("WITHSTORE-#{@token}", "Склад WB")

    importer = Ec::OrderImport::Wb.new

    assert_equal 1, importer.import_unlinked_stats_only_orders(dry_run: true)
    assert_equal 1, importer.import_unlinked_stats_only_orders
    assert_equal 0, importer.import_unlinked_stats_only_orders(dry_run: true)
  end

  def create_marketplace_order(srid:, g_number:)
    RawWb::Order.create!(
      account: @account, wb_order_id: 60_000_000_000 + SecureRandom.random_number(1_000_000_000), srid: srid,
      g_number: g_number, nm_id: @product.product_id.to_i, delivery_type: "fbs", wb_status: "sold",
      supplier_status: "complete"
    )
  end

  def create_stats_order(srid, warehouse_type, g_number: nil)
    RawWb::StatsOrder.create!(
      account: @account, srid: srid, g_number: g_number, nm_id: @product.product_id.to_i, order_date: Time.zone.parse("2026-05-10 10:00:00"),
      warehouse_type: warehouse_type, warehouse_name: "Склад WB РФ", is_cancel: false,
      supplier_article: @sku.sku_code, synced_at: Time.zone.parse("2026-05-10 10:05:00")
    )
  end
end
