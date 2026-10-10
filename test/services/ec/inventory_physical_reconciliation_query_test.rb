require "test_helper"

class Ec::InventoryPhysicalReconciliationQueryTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(6).upcase
    @sku = Ec::Sku.create!(sku_code: "PHYSICAL-#{@token}", product_name: "Physical reconciliation")
    @wb_account = RawWb::SellerAccount.create!(
      name: "wb-physical-#{@token}", api_token: "token-#{@token}", company_type: "small"
    )
    @ozon_account = RawOzon::SellerAccount.create!(
      company_name: "ozon-physical-#{@token}", client_id: "client-#{@token}",
      api_key: "key-#{@token}", company_type: "small"
    )
    @wb_store = Ec::Store.create!(
      platform: "wb", store_name: "WB Physical #{@token}", company_type: "small",
      wb_raw_account_id: @wb_account.id, is_active: true
    )
    @ozon_store = Ec::Store.create!(
      platform: "ozon", store_name: "Ozon Physical #{@token}", company_type: "small",
      ozon_raw_account_id: @ozon_account.id, is_active: true
    )
    @wb_product = Ec::SkuProduct.create!(
      sku_code: @sku.sku_code, store: @wb_store, product_id: (90_000_000 + @token.to_i(16) % 1_000_000).to_s
    )
    @ozon_product = Ec::SkuProduct.create!(
      sku_code: @sku.sku_code, store: @ozon_store, product_id: "OZON-#{@token}",
      platform_sku_id: (80_000_000 + @token.to_i(16) % 1_000_000).to_s
    )
  end

  teardown do
    RawOzon::SupplyOrderItem.where(supply_order_id: RawOzon::SupplyOrder.where(account_id: @ozon_account&.id)).delete_all
    RawOzon::SupplyOrder.where(account_id: @ozon_account&.id).delete_all
    RawWb::SupplyItem.where(account_id: @wb_account&.id).delete_all
    RawWb::Supply.where(account_id: @wb_account&.id).delete_all
    RawOzon::RemovalItem.where(account_id: @ozon_account&.id).delete_all
    Ec::SkuInventoryLevel.where(sku_code: @sku&.sku_code).delete_all
    return_ids = Ec::Return.where(store_id: [ @wb_store&.id, @ozon_store&.id ].compact).select(:id)
    Ec::ReturnSourceLink.where(return_id: return_ids).delete_all
    Ec::ReturnItem.where(return_id: return_ids).delete_all
    Ec::Return.where(id: return_ids).delete_all
    Ec::OrderSourceLink.where(
      order_id: Ec::Order.where(store_id: [ @wb_store&.id, @ozon_store&.id ].compact).select(:id)
    ).delete_all
    Ec::OrderItem.where(store_id: [ @wb_store&.id, @ozon_store&.id ].compact).delete_all
    Ec::OrderFulfillment.where(store_id: [ @wb_store&.id, @ozon_store&.id ].compact).delete_all
    Ec::Order.where(store_id: [ @wb_store&.id, @ozon_store&.id ].compact).delete_all
    RawWb::GoodsReturn.where(account_id: @wb_account&.id).delete_all
    RawWb::Order.where(account_id: @wb_account&.id).delete_all
    Ec::SkuProduct.where(sku_code: @sku&.sku_code).delete_all
    Ec::Store.where(id: [ @wb_store&.id, @ozon_store&.id ].compact).delete_all
    RawWb::SellerAccount.where(id: @wb_account&.id).delete_all
    RawOzon::SellerAccount.where(id: @ozon_account&.id).delete_all
    Ec::SkuBatch.where(sku_code: @sku&.sku_code).delete_all
    Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
  end

  test "builds expected physical stock and keeps returns removals and supplies as separate flows" do
    create_returns
    create_removals
    create_supplies
    fbs_level = Ec::SkuInventoryLevel.create!(
      sku_code: @sku.sku_code, platform: "wb", account_id: @wb_account.id,
      store: @wb_store, store_name: @wb_store.store_name, fulfillment_type: "fbs",
      quantity: 14, is_latest: true, synced_at: Time.current, metadata: {}
    )
    overview = { summary: { received_quantity: 200, available_stock: 20 }, latest_levels: [ fbs_level ] }
    order_distribution = {
      rows: [
        { platform: "wb", store_label: "WB", fulfillment_type: "fbs", status_key: "awaiting_preparation",
          source_status_label: "waiting / new", stocktake_relevant: true, quantity: 3 },
        { platform: "ozon", store_label: "Ozon", fulfillment_type: "fbs", status_key: "in_transit",
          source_status_label: "delivering", stocktake_relevant: false, quantity: 9 }
      ]
    }

    result = Ec::InventoryPhysicalReconciliationQuery.new(
      @sku, overview: overview, order_distribution: order_distribution
    ).call

    assert_equal 96, result.dig(:summary, :expected_physical_stock)
    assert_equal 200, result.dig(:summary, :received_quantity)
    assert_equal 9, result.dig(:summary, :fbs_departed_quantity)
    assert_equal 3, result.dig(:summary, :fbs_not_departed_quantity)
    assert_equal 12, result.dig(:summary, :fbs_order_quantity)
    assert_equal 107, result.dig(:summary, :platform_supply_departed_quantity)
    assert_equal 3, result.dig(:summary, :wb_supply_reconciliation_quantity)
    assert_equal 24, result.dig(:summary, :pending_supply_quantity)
    assert_equal 6, result.dig(:summary, :seller_received_return_quantity)
    assert_equal 6, result.dig(:summary, :ozon_seller_received_removal_quantity)
    assert_equal 5, result.dig(:summary, :removal_to_seller_quantity)
    assert_equal [ [ 3, false ], [ 9, true ] ],
      result[:fbs_order_rows].map { |row| [ row[:quantity], row[:physical_deducted] ] }
    assert_equal 10, result[:supply_rows].size
    assert_equal({ page: 1, page_size: 10, total_count: 13, total_pages: 2 }, result[:supply_pagination])
    assert_equal 7, result[:supply_rows].find { |row| row[:status] == 5 }[:deducted_quantity]
    assert_equal 3, result[:supply_rows].find { |row| row[:status] == 5 }[:reconciliation_quantity]
    assert_equal 4, result.dig(:return_pagination, :total_count)
    assert_equal 2, result[:return_rows].count { |row| row[:physical_included] }
    assert_equal "defective_product",
      result[:return_rows].find { |row| row[:external_return_id] == "OZON-RECEIVED-#{@token}" }[:return_reason_key]
    assert_equal "defect_return",
      result[:return_rows].find { |row| row[:external_return_id] == "WB-RETURN-#{@token}" }[:return_reason_key]
    assert_equal 10, result.dig(:return_pagination, :page_size)
    assert_equal 4, result[:removal_rows].sum { |row| row[:record_count] }
    assert_equal "physical_included_directly",
      result[:removal_rows].find { |row| row[:platform] == "ozon" && row[:movement_key] == "received" }[:physical_impact_key]
    assert_equal "physical_included_via_return",
      result[:removal_rows].find { |row| row[:platform] == "wb" && row[:movement_key] == "received" }[:physical_impact_key]
    assert_equal [ "physical_excluded" ], result[:removal_rows]
      .select { |row| row[:movement_key].in?(%w[in_transit disposed]) }
      .map { |row| row[:physical_impact_key] }.uniq
    assert_equal "ozon_seller_received_removal_quantity", result[:formula].last[:key]
    second_supply_page = Ec::InventoryPhysicalReconciliationQuery.new(
      @sku, overview: overview, order_distribution: order_distribution, supply_page: 2
    ).call
    assert_equal 3, second_supply_page[:supply_rows].size
    assert_equal 2, second_supply_page.dig(:supply_pagination, :page)
    assert_equal 96, second_supply_page.dig(:summary, :expected_physical_stock)
    filtered = Ec::InventoryPhysicalReconciliationQuery.new(
      @sku,
      overview: overview,
      order_distribution: order_distribution,
      return_filters: {
        q: I18n.t("reports.inventory.drawer.physical_stocktake.return_reasons.wb.defect_return"),
        platform: "wb",
        location: "unknown",
        physical_impact: "included"
      }
    ).call

    assert_equal [ "WB-RETURN-#{@token}" ], filtered[:return_rows].map { |row| row[:external_return_id] }
    assert_equal 1, filtered.dig(:return_pagination, :total_count)
  end

  test "physical stocktake adjustments affect only expected physical stock" do
    Ec::SkuBatch.create!(
      sku_code: @sku.sku_code,
      batch_code: "PHYSICAL-ADJUSTMENT-#{@token}",
      status: "received",
      batch_type: :physical_stocktake_adjustment,
      purchased_quantity: -4,
      received_quantity: -4,
      purchase_unit_price_cny: 0
    )

    overview = @sku.inventory_overview
    result = Ec::InventoryPhysicalReconciliationQuery.new(
      @sku,
      overview: overview,
      order_distribution: { rows: [] }
    ).call

    assert_equal 0, overview.dig(:summary, :received_quantity)
    assert_equal 0, overview.dig(:summary, :book_stock)
    assert_equal(-4, result.dig(:summary, :physical_stocktake_adjustment_quantity))
    assert_equal(-4, result.dig(:summary, :expected_physical_stock))
    assert_equal "physical_stocktake_adjustment_quantity", result[:formula].second[:key]
  end

  test "does not add seller-received WB FBW returns to physical stock" do
    order = Ec::Order.create!(
      platform: "wb", store: @wb_store, order_key: "WB-FBW-RETURN-#{@token}", order_status: "delivered"
    )
    fulfillment = order.fulfillments.create!(
      platform: "wb", store: @wb_store,
      external_fulfillment_id: "WB-FBW-RETURN-F-#{@token}",
      fulfillment_key: "WB-FBW-RETURN-F-#{@token}", fulfillment_type: "fbw", status: "delivered"
    )
    returned = Ec::Return.create!(
      platform: "wb", store: @wb_store, order: order, return_key: "WB-FBW-RETURN-#{@token}",
      return_type: "customer_return", process_status: "completed", inventory_location: "seller_warehouse",
      inventory_condition: "defective", refund_status: "none", source_status: "Выдано",
      returned_to_seller_at: Time.current
    )
    returned.items.create!(
      platform: "wb", store: @wb_store, sku_product: @wb_product, order_item: nil,
      item_key: "WB-FBW-RETURN-ITEM-#{@token}", quantity: 4, restockable: true
    )

    result = Ec::InventoryPhysicalReconciliationQuery.new(
      @sku, overview: { summary: { received_quantity: 20 } }, order_distribution: { rows: [] }
    ).call

    assert_equal 0, result.dig(:summary, :seller_received_return_quantity)
    assert_equal false, result[:return_rows].sole[:physical_included]
    assert_equal 4, result[:return_rows].sole[:quantity]
    assert_equal 0, fulfillment.items.count
  end

  test "counts FBS orders cancelled after dispatch as departed once the seller received the return" do
    create_cancelled_ozon_fbs_order("RETURNED", return_status: "ReceivedBySeller", quantity: 2)
    create_cancelled_ozon_fbs_order("NEVER-SHIPPED")
    create_cancelled_ozon_fbs_order("COMING-BACK", return_status: "MovingToSeller", quantity: 3)
    order_distribution = {
      rows: [
        { platform: "ozon", store_label: "Ozon", fulfillment_type: "fbs", status_key: "delivered_confirmed",
          source_status_label: "delivered", stocktake_relevant: false, quantity: 5 }
      ]
    }

    result = Ec::InventoryPhysicalReconciliationQuery.new(
      @sku, overview: { summary: { received_quantity: 10 } }, order_distribution: order_distribution
    ).call

    assert_equal 7, result.dig(:summary, :fbs_departed_quantity)
    assert_equal 2, result.dig(:summary, :seller_received_return_quantity)
    assert_equal 5, result.dig(:summary, :expected_physical_stock)
    assert_equal 1, result.dig(:summary, :fbs_not_departed_quantity)
    assert_equal 8, result.dig(:summary, :fbs_order_quantity)
    cancelled_row = result[:fbs_order_rows].find { |row| row[:status_key] == "cancelled_returned_to_seller" }
    assert_equal [ 2, true, "ozon", "fbs" ],
      [ cancelled_row[:quantity], cancelled_row[:physical_deducted], cancelled_row[:platform], cancelled_row[:fulfillment_type] ]
    undispatched_row = result[:fbs_order_rows].find { |row| row[:status_key] == "cancelled_before_dispatch" }
    assert_equal [ 1, false, "ozon", "fbs" ],
      [ undispatched_row[:quantity], undispatched_row[:physical_deducted], undispatched_row[:platform],
        undispatched_row[:fulfillment_type] ]
    assert_equal 3, result[:fbs_order_rows].size
  end

  test "deducts WB FBS orders cancelled after dispatch until the return arrives and only shows undispatched ones" do
    create_cancelled_wb_order("NEVER-SHIPPED", fulfillment_type: "fbs", source_substatus: "cancel", quantity: 2)
    create_cancelled_wb_order("HANDED-OVER", fulfillment_type: "fbs", source_substatus: "complete")
    create_cancelled_wb_order("FBW", fulfillment_type: "fbw", source_substatus: "complete")
    # The fulfillment substatus reads `cancelled` but the raw WB order is `complete`: it left the warehouse.
    stale = create_cancelled_wb_order("STALE-SUBSTATUS", fulfillment_type: "fbs", source_substatus: "cancelled")
    raw_order = RawWb::Order.create!(
      account: @wb_account, wb_order_id: 70_000_000_000 + @token.to_i(16), nm_id: @wb_product.product_id.to_i,
      delivery_type: "fbs", wb_status: "canceled_by_client", supplier_status: "complete"
    )
    Ec::OrderSourceLink.create!(
      order: stale.order, platform: "wb", source_type: "RawWb::Order", source_id: raw_order.id,
      source_role: "primary", source_key: raw_order.wb_order_id.to_s
    )
    returned = create_cancelled_wb_order("RETURNED", fulfillment_type: "fbs", source_substatus: "complete")
    return_record = Ec::Return.create!(
      platform: "wb", store: @wb_store, order: returned.order, return_key: "WB-CANCELLED-RETURNED-#{@token}",
      return_type: "cancellation_return", process_status: "completed", source_status: "Выдано",
      returned_to_seller_at: Time.current, external_return_id: "WB-CANCELLED-RETURNED-#{@token}"
    )
    return_record.items.create!(
      platform: "wb", store: @wb_store, sku_product: @wb_product,
      item_key: "WB-CANCELLED-RETURNED-ITEM-#{@token}", quantity: 1, restockable: true
    )

    result = Ec::InventoryPhysicalReconciliationQuery.new(
      @sku, overview: { summary: { received_quantity: 10 } }, order_distribution: { rows: [] }
    ).call

    rows = result[:fbs_order_rows].group_by { |row| row[:status_key] }.transform_values { |list| list.sum { |row| row[:quantity] } }
    assert_equal(
      { "cancelled_before_dispatch" => 2, "cancelled_dispatched_return_pending" => 2, "cancelled_returned_to_seller" => 1 },
      rows
    )
    assert_equal [ false ], result[:fbs_order_rows].select { |row| row[:status_key] == "cancelled_before_dispatch" }
      .map { |row| row[:physical_deducted] }
    assert_equal 3, result.dig(:summary, :fbs_departed_quantity)
    assert_equal 1, result.dig(:summary, :seller_received_return_quantity)
    assert_equal 8, result.dig(:summary, :expected_physical_stock)
  end

  private

  def create_cancelled_ozon_fbs_order(suffix, return_status: nil, quantity: 1)
    order = Ec::Order.create!(
      platform: "ozon", store: @ozon_store, order_key: "ozon:CANCELLED-#{suffix}-#{@token}",
      external_order_id: "OZON-CANCELLED-#{suffix}-#{@token}", order_status: "cancelled"
    )
    fulfillment = order.fulfillments.create!(
      platform: "ozon", store: @ozon_store,
      external_fulfillment_id: "OZON-CANCELLED-#{suffix}-F-#{@token}",
      fulfillment_key: "OZON-CANCELLED-#{suffix}-F-#{@token}", fulfillment_type: "fbs", status: "cancelled",
      source_status: "cancelled", source_substatus: "posting_canceled"
    )
    Ec::OrderItem.create!(
      platform: "ozon", store: @ozon_store, order: order, fulfillment: fulfillment,
      external_item_id: "OZON-CANCELLED-#{suffix}-ITEM-#{@token}",
      platform_sku_id: @ozon_product.platform_sku_id, sku_code: @sku.sku_code, quantity: quantity
    )
    return unless return_status

    returned = Ec::Return.create!(
      platform: "ozon", store: @ozon_store, order: order, return_key: "OZON-CANCELLED-#{suffix}-RETURN-#{@token}",
      return_type: "cancellation_return", process_status: "received_by_seller",
      inventory_location: "seller_warehouse", source_status: return_status,
      external_return_id: "OZON-CANCELLED-#{suffix}-RETURN-#{@token}", requested_at: 1.day.ago
    )
    returned.items.create!(
      platform: "ozon", store: @ozon_store, sku_product: @ozon_product,
      item_key: "OZON-CANCELLED-#{suffix}-ITEM-#{@token}", quantity: quantity, restockable: true
    )
  end

  def create_cancelled_wb_order(suffix, fulfillment_type:, source_substatus:, quantity: 1)
    order = Ec::Order.create!(
      platform: "wb", store: @wb_store, order_key: "wb:CANCELLED-#{suffix}-#{@token}",
      external_order_id: "WB-CANCELLED-#{suffix}-#{@token}", order_status: "cancelled"
    )
    fulfillment = order.fulfillments.create!(
      platform: "wb", store: @wb_store,
      external_fulfillment_id: "WB-CANCELLED-#{suffix}-F-#{@token}",
      fulfillment_key: "WB-CANCELLED-#{suffix}-F-#{@token}", fulfillment_type: fulfillment_type,
      status: "cancelled", source_status: "canceled_by_client", source_substatus: source_substatus
    )
    Ec::OrderItem.create!(
      platform: "wb", store: @wb_store, order: order, fulfillment: fulfillment,
      external_item_id: "WB-CANCELLED-#{suffix}-ITEM-#{@token}",
      platform_sku_id: @wb_product.product_id, sku_code: @sku.sku_code, quantity: quantity
    )
  end

  def create_returns
    order = Ec::Order.create!(
      platform: "ozon", store: @ozon_store, order_key: "ozon:#{@token}",
      external_order_id: "OZON-ORDER-#{@token}", order_status: "delivered"
    )
    returned_to_ozon = Ec::Return.create!(
      platform: "ozon", store: @ozon_store, order: order, return_key: "OZON-RETURN-#{@token}",
      return_type: "customer_return", process_status: "at_platform",
      inventory_location: "platform_return_warehouse", source_status: "ReturnedToOzon",
      external_return_id: "OZON-RETURN-#{@token}", requested_at: 3.days.ago
    )
    returned_to_ozon.items.create!(
      platform: "ozon", store: @ozon_store, sku_product: @ozon_product,
      item_key: "OZON-RETURN-ITEM-#{@token}", quantity: 2, restockable: true
    )
    moving_to_seller = Ec::Return.create!(
      platform: "ozon", store: @ozon_store, order: order, return_key: "OZON-MOVING-#{@token}",
      return_type: "customer_return", process_status: "moving_to_seller",
      inventory_location: "seller_return_transit", source_status: "MovingToSeller",
      external_return_id: "OZON-MOVING-#{@token}", requested_at: 2.days.ago
    )
    moving_to_seller.items.create!(
      platform: "ozon", store: @ozon_store, sku_product: @ozon_product,
      item_key: "OZON-MOVING-ITEM-#{@token}", quantity: 4, restockable: false
    )
    received_by_seller = Ec::Return.create!(
      platform: "ozon", store: @ozon_store, order: order, return_key: "OZON-RECEIVED-#{@token}",
      return_type: "customer_return", process_status: "received_by_seller",
      inventory_location: "seller_warehouse", source_status: "ReceivedBySeller",
      source_substatus: "Товар не работает / брак",
      external_return_id: "OZON-RECEIVED-#{@token}", requested_at: 12.hours.ago
    )
    received_by_seller.items.create!(
      platform: "ozon", store: @ozon_store, sku_product: @ozon_product,
      item_key: "OZON-RECEIVED-ITEM-#{@token}", quantity: 5, restockable: true
    )

    raw = RawWb::GoodsReturn.create!(
      account: @wb_account, shk_id: 70_000_000 + @token.to_i(16), nm_id: @wb_product.product_id.to_i,
      status: "Выдано", return_type: "Возврат брака", completed_dt: Time.current, is_status_active: 0,
      synced_at: Time.current
    )
    orderless_return = Ec::Return.create!(
      platform: "wb", store: @wb_store, return_key: "WB-ORDERLESS-#{@token}",
      return_type: "customer_return", process_status: "completed", source_status: "Выдано",
      source_payload: { "return_type" => raw.return_type },
      external_return_id: "WB-RETURN-#{@token}", requested_at: 1.day.ago
    )
    item = orderless_return.items.create!(
      platform: "wb", store: @wb_store, sku_product: @wb_product,
      item_key: "WB-ORDERLESS-ITEM-#{@token}", quantity: 1, restockable: true
    )
    Ec::ReturnSourceLink.create!(
      return: orderless_return, item: item, platform: "wb", source_type: "RawWb::GoodsReturn",
      source_id: raw.id, source_key: raw.shk_id.to_s, synced_at: Time.current
    )
  end

  def create_removals
    create_ozon_removal("TRANSIT", state: "В пути", quantity: 5)
    create_ozon_removal("RECEIVED", state: "Завершено", box_state: "Получена", quantity: 6)
    create_ozon_removal("DISPOSED", state: "Завершено", box_state: "Утилизирована", quantity: 7)
  end

  def create_ozon_removal(suffix, state:, quantity:, box_state: nil)
    RawOzon::RemovalItem.create!(
      account: @ozon_account, source_type: "stock", row_key: "#{suffix}-#{@token}",
      return_id: "#{suffix}-#{@token}", sku: @ozon_product.platform_sku_id,
      quantity: quantity, return_state: state, box_state: box_state,
      synced_at: Time.current, raw_json: {}
    )
  end

  def create_supplies
    planned = RawWb::Supply.create!(
      account: @wb_account, wb_supply_id: "WB-PLANNED-#{@token}", status_id: 2, synced_at: Time.current
    )
    RawWb::SupplyItem.create!(
      account: @wb_account, wb_supply_id: planned.wb_supply_id, nm_id: @wb_product.product_id.to_i,
      quantity: 10, accepted_qty: 3, synced_at: Time.current
    )
    9.times do |index|
      extra_pending = RawWb::Supply.create!(
        account: @wb_account, wb_supply_id: "WB-PENDING-#{index}-#{@token}", status_id: 2,
        synced_at: Time.current
      )
      RawWb::SupplyItem.create!(
        account: @wb_account, wb_supply_id: extra_pending.wb_supply_id, nm_id: @wb_product.product_id.to_i,
        quantity: 1, accepted_qty: 0, synced_at: Time.current
      )
    end
    accepted = RawWb::Supply.create!(
      account: @wb_account, wb_supply_id: "WB-ACCEPTED-#{@token}", status_id: 5, synced_at: Time.current
    )
    RawWb::SupplyItem.create!(
      account: @wb_account, wb_supply_id: accepted.wb_supply_id, nm_id: @wb_product.product_id.to_i,
      quantity: 10, accepted_qty: 7, synced_at: Time.current
    )
    draft = RawWb::Supply.create!(
      account: @wb_account, wb_supply_id: "WB-DRAFT-#{@token}", status_id: 1, synced_at: Time.current
    )
    RawWb::SupplyItem.create!(
      account: @wb_account, wb_supply_id: draft.wb_supply_id, nm_id: @wb_product.product_id.to_i,
      quantity: 100, accepted_qty: 0, synced_at: Time.current
    )

    ready = RawOzon::SupplyOrder.create!(
      account: @ozon_account, supply_order_id: "OZON-READY-#{@token}", status: "READY_TO_SUPPLY",
      raw_json: {}, synced_at: Time.current
    )
    ready.supply_order_items.create!(
      ozon_supply_id: 60_000_000 + @token.to_i(16) % 1_000_000, bundle_id: "READY-#{@token}",
      state: "READY_TO_SUPPLY", platform_sku_id: @ozon_product.platform_sku_id.to_i,
      quantity: 8, synced_at: Time.current
    )
    transit = RawOzon::SupplyOrder.create!(
      account: @ozon_account, supply_order_id: "OZON-TRANSIT-#{@token}", status: "IN_TRANSIT",
      raw_json: {}, synced_at: Time.current
    )
    transit.supply_order_items.create!(
      ozon_supply_id: 61_000_000 + @token.to_i(16) % 1_000_000, bundle_id: "TRANSIT-#{@token}",
      state: "IN_TRANSIT", platform_sku_id: @ozon_product.platform_sku_id.to_i,
      quantity: 100, synced_at: Time.current
    )
  end
end
