require "test_helper"

class Ec::InventoryOrderSalesDistributionQueryTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(6).upcase
    @sku = Ec::Sku.create!(sku_code: "ORDER-DIST-#{@token}", product_name: "订单分布测试")
    @wb_account = RawWb::SellerAccount.create!(name: "wb-dist-#{@token}", api_token: "token-#{@token}", company_type: "small")
    @ozon_account = RawOzon::SellerAccount.create!(company_name: "ozon-dist-#{@token}", client_id: "client-#{@token}", api_key: "key-#{@token}", company_type: "small")
    @wb_store = Ec::Store.create!(platform: "wb", store_name: "WB #{@token}", company_type: "small", wb_raw_account_id: @wb_account.id, is_active: true)
    @ozon_store = Ec::Store.create!(platform: "ozon", store_name: "Ozon #{@token}", company_type: "small", ozon_raw_account_id: @ozon_account.id, is_active: true)
    Ec::SkuProduct.create!(sku_code: @sku.sku_code, store: @wb_store, product_id: "WB-#{@token}")
    Ec::SkuProduct.create!(sku_code: @sku.sku_code, store: @ozon_store, product_id: "OZON-#{@token}", platform_sku_id: "98#{@token.to_i(16)}")
  end

  teardown do
    store_ids = [@wb_store&.id, @ozon_store&.id].compact
    order_ids = Ec::Order.where(store_id: store_ids).select(:id)
    Ec::OrderSourceLink.where(order_id: order_ids).delete_all
    Ec::OrderItem.where(store_id: store_ids).delete_all
    Ec::OrderFulfillment.where(store_id: store_ids).delete_all
    Ec::Order.where(store_id: store_ids).delete_all
    RawWb::StatsSale.where(account_id: @wb_account&.id).delete_all
    RawWb::StatsOrder.where(account_id: @wb_account&.id).delete_all
    Ec::SkuProduct.where(sku_code: @sku&.sku_code).delete_all
    Ec::Store.where(id: store_ids).delete_all
    RawWb::SellerAccount.where(id: @wb_account&.id).delete_all
    RawOzon::SellerAccount.where(id: @ozon_account&.id).delete_all
    Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
  end

  test "separates fulfillment and raw stages without changing deducted sales" do
    add_item(@wb_store, "fbs", "processing", "waiting", "new", 2)
    add_item(@wb_store, "fbs", "processing", "waiting", "complete", 3)
    add_item(@wb_store, "fbs", "delivered", "waiting", "complete", 5, fulfillment_status: "processing")
    fbw_order = add_item(@wb_store, "fbw", "processing", nil, nil, 4)
    add_stats_evidence(fbw_order, sale_ids: ["S-#{@token}-FBW"])
    add_item(@ozon_store, "fbs", "processing", "awaiting_packaging", "posting_created", 6)
    add_item(@ozon_store, "fbs", "processing", "awaiting_deliver", "posting_transferring_to_delivery", 7)
    add_item(@ozon_store, "fbo", "processing", "awaiting_packaging", "posting_created", 8)
    add_item(@ozon_store, "fbs", "shipped", "delivering", "posting_on_way_to_city", 9)
    add_item(@ozon_store, "fbs", "cancelled", "cancelled", "posting_canceled", 10)
    add_item(@ozon_store, nil, "processing", nil, nil, 11)
    add_item(@ozon_store, "fbs", "processing", "awaiting_packaging", "posting_created", 12, platform_sku_id: "UNBOUND-#{@token}")

    distribution = Ec::InventoryOrderSalesDistributionQuery.new(@sku).call
    rows = distribution[:rows]

    assert_equal 9, rows.size
    assert_equal 3, rows.find { |row| row[:platform] == "wb" && row[:status_key] == "handover_pending" }[:quantity]
    assert_equal 2, rows.find { |row| row[:platform] == "wb" && row[:status_key] == "awaiting_preparation" }[:quantity]
    assert rows.find { |row| row[:platform] == "wb" && row[:status_key] == "handover_pending" }[:stocktake_relevant]
    assert rows.find { |row| row[:platform] == "ozon" && row[:status_key] == "awaiting_preparation" }[:stocktake_relevant]
    assert_equal 5, rows.find { |row| row[:platform] == "wb" && row[:status_key] == "sold_confirmed" && row[:fulfillment_type] == "fbs" }[:quantity]
    fbw_row = rows.find { |row| row[:fulfillment_type] == "fbw" }
    assert_equal 4, fbw_row[:quantity]
    assert_equal "sold_confirmed", fbw_row[:status_key]
    assert_equal I18n.t("reports.inventory.drawer.sales_distribution.evidence.wb_stats_sale"), fbw_row[:evidence_label]
    assert fbw_row[:needs_status_repair]
    assert_equal 7, rows.find { |row| row[:platform] == "ozon" && row[:status_key] == "handover_pending" }[:quantity]
    assert_equal 8, rows.find { |row| row[:fulfillment_type] == "fbo" }[:quantity]
    assert_not rows.find { |row| row[:fulfillment_type] == "fbo" }[:stocktake_relevant]
    assert_equal 11, rows.find { |row| row[:fulfillment_type] == "unknown" }[:quantity]
    assert_equal 55, distribution.dig(:summary_row, :quantity)
    assert_equal @sku.inventory_overview.dig(:summary, :sales_quantity), distribution.dig(:summary_row, :quantity)
  end

  test "infers fbw outcomes from stats sales returns and cancellation evidence" do
    sold = add_item(@wb_store, "fbw", "processing", nil, nil, 1)
    returned = add_item(@wb_store, "fbw", "processing", nil, nil, 2)
    cancelled = add_item(@wb_store, "fbw", "processing", nil, nil, 3)
    unresolved = add_item(@wb_store, "fbw", "processing", nil, nil, 4)
    add_stats_evidence(sold, sale_ids: ["S-#{@token}-SOLD"])
    add_stats_evidence(returned, sale_ids: ["S-#{@token}-RETURNED", "R-#{@token}-RETURNED"])
    add_stats_evidence(cancelled, is_cancel: true)
    add_stats_evidence(unresolved)

    rows = Ec::InventoryOrderSalesDistributionQuery.new(@sku).call[:rows]

    assert_equal({
      "sold_confirmed" => 1,
      "returned_confirmed" => 2,
      "cancelled_confirmed" => 3,
      "outcome_unknown" => 4
    }, rows.to_h { |row| [row[:status_key], row[:quantity]] })
    assert rows.reject { |row| row[:status_key] == "outcome_unknown" }.all? { |row| row[:needs_status_repair] }
    assert_not rows.find { |row| row[:status_key] == "outcome_unknown" }[:needs_status_repair]
  end

  test "shows only orders that are deducted from book inventory" do
    add_item(@wb_store, "fbw", "returned", nil, nil, 2)
    add_item(@wb_store, "fbs", "returned", nil, nil, 3)
    add_item(@wb_store, nil, "returned", nil, nil, 4)
    add_item(@ozon_store, "fbo", "returned", nil, nil, 5)

    distribution = Ec::InventoryOrderSalesDistributionQuery.new(@sku).call

    assert_not distribution[:rows].any? { |row| row[:platform] == "wb" && row[:fulfillment_type] == "fbw" }
    assert_equal 12, distribution.dig(:summary_row, :quantity)
    assert_equal @sku.inventory_overview.dig(:summary, :sales_quantity), distribution.dig(:summary_row, :quantity)
  end

  test "treats an Ozon posting in carriage as in transit rather than awaiting handover" do
    add_item(@ozon_store, "fbs", "processing", "awaiting_deliver", "posting_in_carriage", 2)

    row = Ec::InventoryOrderSalesDistributionQuery.new(@sku).call[:rows].sole

    assert_equal "in_transit", row[:status_key]
    assert_not row[:stocktake_relevant]
  end

  private

  def add_item(store, fulfillment_type, order_status, source_status, source_substatus, quantity, fulfillment_status: nil, platform_sku_id: nil)
    identifier = SecureRandom.hex(8)
    order = Ec::Order.create!(platform: store.platform, store: store, order_key: "#{store.platform}:#{store.id}:#{identifier}",
      external_order_id: identifier, order_status: order_status, synced_at: Time.current)
    fulfillment = if fulfillment_type
      Ec::OrderFulfillment.create!(platform: store.platform, store: store, order: order,
        external_fulfillment_id: identifier, fulfillment_key: "#{store.platform}:#{store.id}:#{identifier}",
        fulfillment_type: fulfillment_type, status: fulfillment_status || order_status,
        source_status: source_status, source_substatus: source_substatus)
    end
    Ec::OrderItem.create!(platform: store.platform, store: store, order: order, fulfillment: fulfillment,
      external_item_id: identifier, platform_sku_id: platform_sku_id || (store.wb? ? "WB-#{@token}" : "98#{@token.to_i(16)}"),
      sku_code: @sku.sku_code, quantity: quantity)
    order
  end

  def add_stats_evidence(order, is_cancel: false, sale_ids: [])
    identifier = SecureRandom.hex(8)
    stats_order = RawWb::StatsOrder.create!(
      account: @wb_account,
      g_number: "G-#{identifier}",
      order_date: Time.current,
      last_change_date: Time.current,
      warehouse_type: "Склад WB",
      is_cancel: is_cancel,
      cancel_date: is_cancel ? Time.current : nil,
      srid: "SRID-#{identifier}",
      synced_at: Time.current
    )
    fulfillment = order.fulfillments.first
    fulfillment.update!(raw_source_type: "RawWb::StatsOrder", raw_source_id: stats_order.id)
    Ec::OrderSourceLink.create!(
      order: order,
      fulfillment: fulfillment,
      platform: "wb",
      source_type: "RawWb::StatsOrder",
      source_id: stats_order.id,
      source_key: stats_order.srid,
      source_role: "primary",
      synced_at: Time.current
    )
    sale_ids.each do |sale_id|
      RawWb::StatsSale.create!(
        account: @wb_account,
        sale_id: sale_id,
        g_number: stats_order.g_number,
        sale_date: Time.current,
        last_change_date: Time.current,
        srid: stats_order.srid,
        synced_at: Time.current
      )
    end
  end
end
