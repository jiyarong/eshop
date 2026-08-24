require "test_helper"

class SupplyOrderReports::ReportQueryTest < ActiveSupport::TestCase
  test "uses ten rows per page" do
    assert_equal 10, SupplyOrderReports::ReportQuery::PER_PAGE
  end

  setup do
    @token = SecureRandom.hex(5).upcase
    @wb_account = RawWb::SellerAccount.create!(name: "Supply WB #{@token}", api_token: "wb-#{@token}", is_active: true, company_type: :small)
    @ozon_account = RawOzon::SellerAccount.create!(company_name: "Supply Ozon #{@token}", client_id: "oz-#{@token}", api_key: "key-#{@token}", is_active: true, company_type: :small)
    @wb_store = Ec::Store.create!(platform: "wb", store_name: "WB #{@token}", company_type: "small", wb_raw_account_id: @wb_account.id)
    @ozon_store = Ec::Store.create!(platform: "ozon", store_name: "Ozon #{@token}", company_type: "small", ozon_raw_account_id: @ozon_account.id)
    @sku = Ec::Sku.create!(sku_code: "SUPPLY-#{@token}", product_name: "Supply product")
    Ec::SkuProduct.create!(sku_code: @sku.sku_code, store: @wb_store, product_id: "#{@token.hex % 1_000_000}")
    Ec::SkuProduct.create!(sku_code: @sku.sku_code, store: @ozon_store, product_id: "O-#{@token}", platform_sku_id: "#{@token.hex % 1_000_000 + 1_000_000}")
    @operator = User.create!(email: "supply-operator-#{@token.downcase}@example.com", password: "password123", name: "Supply Operator #{@token}")
    @wb_product = Ec::SkuProduct.find_by!(store: @wb_store)
    Ec::SkuProductOperator.create!(sku_product: @wb_product, user: @operator, role: "operator")
  end

  teardown do
    RawWb::SupplyItem.where(account_id: @wb_account.id).delete_all
    RawWb::Supply.where(account_id: @wb_account.id).delete_all
    RawOzon::SupplyOrder.where(account_id: @ozon_account.id).delete_all
    Ec::SkuProductOperator.where(user_id: @operator.id).delete_all
    Ec::SkuProduct.where(store_id: [@wb_store.id, @ozon_store.id]).delete_all
    Ec::Store.where(id: [@wb_store.id, @ozon_store.id]).delete_all
    Ec::Sku.with_deleted.where(id: @sku.id).delete_all
    @wb_account.destroy!
    @ozon_account.destroy!
    @operator.destroy!
  end

  test "flattens WB supply items and maps the internal SKU" do
    product_id = Ec::SkuProduct.find_by!(store: @wb_store).product_id.to_i
    supply = RawWb::Supply.create!(account: @wb_account, wb_supply_id: "WB-#{@token}", preorder_id: 12345, status_id: 4, box_type_id: 1, supply_date: Time.zone.parse("2026-08-05 10:00"), warehouse_name: "Ryazan", actual_warehouse_name: "Obukhovo", transit_warehouse_name: "Obukhovo", acceptance_cost: 5000, paid_acceptance_coefficient: 10, storage_coefficient: 140, delivery_coefficient: 125, detail_quantity: 12, accepted_quantity: 5, synced_at: Time.current)
    RawWb::SupplyItem.create!(account: @wb_account, wb_supply_id: supply.wb_supply_id, nm_id: product_id, quantity: 12, accepted_qty: 5, synced_at: Time.current)

    report = SupplyOrderReports::ReportQuery.new(params: { store_ref: "wb:#{@wb_account.id}" }).call

    assert_equal "wb", report.dig(:meta, :platform)
    assert_equal 1, report[:rows].size
    assert_equal({ supply_id: supply.wb_supply_id, platform_item_id: product_id, sku_code: @sku.sku_code, quantity: 12, accepted_quantity: 5, remaining_quantity: 7 }, report[:rows].first.slice(:supply_id, :platform_item_id, :sku_code, :quantity, :accepted_quantity, :remaining_quantity))
    assert_equal({ warehouse_name: "Ryazan", actual_warehouse_name: "Obukhovo", transit_warehouse_name: "Obukhovo", acceptance_cost: 5000.to_d, supply_quantity: 12, supply_accepted_quantity: 5 }, report[:rows].first.slice(:warehouse_name, :actual_warehouse_name, :transit_warehouse_name, :acceptance_cost, :supply_quantity, :supply_accepted_quantity))
  end

  test "allows the ERP AI endpoint to request one hundred rows per page" do
    report = SupplyOrderReports::ReportQuery.new(
      params: { store_ref: "wb:#{@wb_account.id}" },
      per_page: 100
    ).call

    assert_equal 100, report.dig(:pagination, :per_page)
  end

  test "orders newest supplies first and filters platform-specific statuses" do
    product_id = Ec::SkuProduct.find_by!(store: @wb_store).product_id.to_i
    older = RawWb::Supply.create!(account: @wb_account, wb_supply_id: "WB-OLD-#{@token}", preorder_id: 22345, status_id: 4, supply_created_at: 2.days.ago, synced_at: Time.current)
    newer = RawWb::Supply.create!(account: @wb_account, wb_supply_id: "WB-NEW-#{@token}", preorder_id: 32345, status_id: 5, supply_created_at: 1.day.ago, synced_at: Time.current)
    [older, newer].each { |supply| RawWb::SupplyItem.create!(account: @wb_account, wb_supply_id: supply.wb_supply_id, nm_id: product_id, quantity: 1, accepted_qty: 0, synced_at: Time.current) }

    report = SupplyOrderReports::ReportQuery.new(params: { store_ref: "wb:#{@wb_account.id}" }).call
    assert_equal [newer.wb_supply_id, older.wb_supply_id], report[:rows].map { |row| row[:supply_id] }
    assert_equal [{ status: 4, count: 1 }, { status: 5, count: 1 }], report[:status_summary]

    filtered = SupplyOrderReports::ReportQuery.new(params: { store_ref: "wb:#{@wb_account.id}", statuses: ["4", "COMPLETED"] }).call
    assert_equal [older.wb_supply_id], filtered[:rows].map { |row| row[:supply_id] }
    assert_equal [{ status: 4, count: 1 }], filtered[:status_summary]
  end

  test "filters by the operator binding scoped to the selected store product" do
    product_id = @wb_product.product_id.to_i
    supply = RawWb::Supply.create!(account: @wb_account, wb_supply_id: "WB-OP-#{@token}", preorder_id: 42345, status_id: 4, supply_created_at: Time.current, synced_at: Time.current)
    RawWb::SupplyItem.create!(account: @wb_account, wb_supply_id: supply.wb_supply_id, nm_id: product_id, quantity: 2, accepted_qty: 0, synced_at: Time.current)

    matched = SupplyOrderReports::ReportQuery.new(params: { store_ref: "wb:#{@wb_account.id}", operator_id: @operator.id }).call
    assert_equal [supply.wb_supply_id], matched[:rows].map { |row| row[:supply_id] }

    other = User.create!(email: "other-#{@token.downcase}@example.com", password: "password123")
    unmatched = SupplyOrderReports::ReportQuery.new(params: { store_ref: "wb:#{@wb_account.id}", operator_id: other.id }).call
    assert_empty unmatched[:rows]
  ensure
    other&.destroy!
  end

  test "flattens Ozon item JSON and exposes only stored warehouse data" do
    platform_id = Ec::SkuProduct.find_by!(store: @ozon_store).platform_sku_id
    RawOzon::SupplyOrder.create!(account: @ozon_account, supply_order_id: "SO-#{@token}", status: "COMPLETED", items: { platform_id => 8 }, timeslot: { "from" => "2026-08-05T10:00:00Z" }, raw_json: { "order_number" => "ORD-#{@token}", "drop_off_warehouse" => { "name" => "Minsk drop-off" }, "supplies" => [{ "storage_warehouse" => { "name" => "Minsk storage" } }] }, synced_at: Time.current)

    report = SupplyOrderReports::ReportQuery.new(params: { store_ref: "ozon:#{@ozon_account.id}", sku_codes: [@sku.sku_code] }).call

    assert_equal 1, report[:rows].size
    assert_equal({ order_number: "ORD-#{@token}", platform_item_id: platform_id, sku_code: @sku.sku_code, quantity: 8, origin_warehouse: "Minsk drop-off", destination_warehouses: "Minsk storage" }, report[:rows].first.slice(:order_number, :platform_item_id, :sku_code, :quantity, :origin_warehouse, :destination_warehouses))
  end

  test "keeps Ozon supply items mapped to a soft-deleted SKU" do
    product = Ec::SkuProduct.find_by!(store: @ozon_store)
    product.update!(product_name: "Stored platform product")
    platform_id = product.platform_sku_id
    @sku.destroy!
    RawOzon::SupplyOrder.create!(
      account: @ozon_account,
      supply_order_id: "SO-DELETED-#{@token}",
      status: "READY_TO_SUPPLY",
      items: { platform_id => 3 },
      raw_json: {},
      synced_at: Time.current
    )

    report = SupplyOrderReports::ReportQuery.new(params: { store_ref: "ozon:#{@ozon_account.id}" }).call

    row = report[:rows].sole
    assert_equal @sku.sku_code, row[:sku_code]
    assert_equal "Stored platform product", row[:product_name]
    assert_equal 3, row[:quantity]
  end
end
