require "test_helper"

class Ec::OwnWarehouseFboReceiptsQueryTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(5).upcase
    @week = Date.new(2026, 6, 1)
    @sku = Ec::Sku.create!(sku_code: "RECEIPT-#{@token}")
    @user = User.create!(email: "receipt-#{@token}@example.com", password: "password123")
    @wb = RawWb::SellerAccount.create!(name: @token, api_token: @token, company_type: :small)
    @ozon = RawOzon::SellerAccount.create!(company_name: @token, client_id: @token, api_key: @token, company_type: :small)
    @ws = Ec::Store.create!(platform: "wb", store_name: @token, company_type: "small", wb_raw_account_id: @wb.id)
    @os = Ec::Store.create!(platform: "ozon", store_name: @token, company_type: "small", ozon_raw_account_id: @ozon.id)
    @wp = Ec::SkuProduct.create!(store: @ws, sku_code: @sku.sku_code, product_id: "#{@token.hex}")
    @op = Ec::SkuProduct.create!(store: @os, sku_code: @sku.sku_code, product_id: @token, platform_sku_id: "#{@token.hex}")
  end

  teardown do
    Ec::OperationAction.where(ec_store_id: [@ws.id, @os.id]).delete_all
    RawWb::SupplyItem.where(account_id: @wb.id).delete_all
    RawWb::Supply.where(account_id: @wb.id).delete_all
    RawOzon::SupplyOrderItem.where(supply_order_id: RawOzon::SupplyOrder.where(account_id: @ozon.id).select(:id)).delete_all
    RawOzon::SupplyOrder.where(account_id: @ozon.id).delete_all
    Ec::SkuProduct.where(store_id: [@ws.id, @os.id]).delete_all
    Ec::Store.where(id: [@ws.id, @os.id]).delete_all
    Ec::Snapshot.where(sku_id: @sku.id).delete_all
    Ec::OperationLog.where(record_type: "Ec::Sku", record_id: @sku.id).delete_all
    Ec::Sku.with_deleted.where(id: @sku.id).delete_all
    @wb.destroy!; @ozon.destroy!; @user.destroy!
  end

  test "combines sent quantities across platforms and deduplicates history and listings" do
    wb_supply("WB", "2026-05-31T16:00:00Z", 12)
    order = ozon_supply("OZ", "COMPLETED", "2026-06-15T00:00:00Z", 8)
    2.times { receipt(order, "2026-06-01T00:00:00Z") }
    Ec::SkuProduct.create!(store: @os, sku_code: @sku.sku_code, product_id: "other-#{@token}", platform_sku_id: @op.platform_sku_id)
    result = query
    assert_empty result.issues
    assert_equal 20.to_d, result.quantities.fetch([@sku.sku_code, @week])
    assert_equal({ "wb" => 12.to_d, "ozon" => 8.to_d }, result.by_platform.fetch([@sku.sku_code, @week]))
    # Later completion must not move receipt into a different week.
    assert_empty Ec::OwnWarehouseFboReceiptsQuery.call(week_start: @week + 14, stores: stores).quantities
  end

  test "Shanghai week boundaries and nonreceived orders are excluded" do
    wb_supply("BEFORE", "2026-05-31T15:59:59Z", 3)
    wb_supply("AFTER", "2026-06-07T16:00:00Z", 5)
    ozon_supply("CANCEL", "CANCELLED", "2026-06-02T00:00:00Z", 8)
    ozon_supply("READY", "READY_TO_SUPPLY", "2026-06-02T00:00:00Z", 8)
    result = query
    assert_empty result.quantities
    assert_empty result.issues
  end

  test "current receipt state is valid but completed update is not a receipt fallback" do
    ozon_supply("CURRENT", "ACCEPTED_AT_SUPPLY_WAREHOUSE", "2026-06-02T00:00:00Z", 7)
    unknown = ozon_supply("UNKNOWN", "COMPLETED", "2026-06-03T00:00:00Z", 11)
    result = query
    assert_equal 7.to_d, result.quantities.values.sum
    assert_equal [unknown.supply_order_id], result.issues.map { |issue| issue["reference"] }
    assert_equal "missing_receipt_date", result.issues.first["reason"]
  end

  test "ambiguous SKU mapping is rejected instead of duplicated" do
    supply = RawWb::Supply.create!(account: @wb, wb_supply_id: "UNMAPPED-#{@token}", status_id: 5, fact_date: Time.iso8601("2026-06-02T00:00:00Z"))
    RawWb::SupplyItem.create!(account: @wb, wb_supply_id: supply.wb_supply_id, nm_id: 999_999_999, quantity: 12, accepted_qty: 1)
    result = query
    assert_empty result.quantities
    assert_equal "sku_mapping", result.issues.first["reason"]
  end

  private

  def stores
    Ec::Store.where(id: [@ws.id, @os.id])
  end

  def query
    Ec::OwnWarehouseFboReceiptsQuery.call(week_start: @week, stores: stores)
  end

  def wb_supply(ref, time, qty)
    supply = RawWb::Supply.create!(account: @wb, wb_supply_id: "#{ref}-#{@token}", status_id: 5, fact_date: Time.iso8601(time))
    RawWb::SupplyItem.create!(account: @wb, wb_supply_id: supply.wb_supply_id, nm_id: @wp.product_id.to_i, quantity: qty, accepted_qty: 1)
  end

  def ozon_supply(ref, status, updated_at, qty)
    order = RawOzon::SupplyOrder.create!(account: @ozon, supply_order_id: "#{ref}-#{@token}", status: status,
      created_at: Time.iso8601("2026-05-01T00:00:00Z"), raw_json: { state_updated_date: updated_at })
    order.supply_order_items.create!(ozon_supply_id: @token.hex, platform_sku_id: @op.platform_sku_id, state: status, bundle_id: "bundle-#{ref}-#{@token}", quantity: qty)
    order
  end

  def receipt(order, time)
    Ec::OperationAction.create!(sku: @sku, sku_product: @op, store: @os, operated_by_user: @user,
      operation_type: "supply_order", operated_at: Time.iso8601(time), diff_result: {
        platform: "ozon", supply_order: { id: order.supply_order_id, account_id: "#{@ozon.id}.0", state_updated_at: time },
        fields: { supply_order_status: { from: "READY_TO_SUPPLY", to: "ACCEPTED_AT_SUPPLY_WAREHOUSE" } }
      })
  end
end
