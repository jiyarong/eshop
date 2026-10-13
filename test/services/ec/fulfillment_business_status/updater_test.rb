require "test_helper"
require_relative "../../../support/book_ledger_fixtures"

class Ec::FulfillmentBusinessStatus::UpdaterTest < ActiveSupport::TestCase
  include BookLedgerFixtures

  setup { setup_ledger_world }
  teardown do
    RawWb::StatsSale.where(account_id: @wb_account&.id).delete_all
    RawWb::StatsOrder.where(account_id: @wb_account&.id).delete_all
    teardown_ledger_world
  end

  def statuses(fulfillment)
    fulfillment.reload.attributes.values_at("business_status", "return_business_status")
  end

  test "Ozon delivered posting with a seller received return" do
    order = ledger_order(platform: "ozon", status: "delivered", source_status: "delivered",
      source_substatus: "posting_received")
    ledger_return(order, source_status: "ReceivedBySeller")
    fulfillment = order.fulfillments.first

    result = Ec::FulfillmentBusinessStatus::Updater.call(fulfillment)

    assert_equal %w[returned received_by_seller], [ result.business_status, result.return_business_status ]
    assert_equal %w[returned received_by_seller], statuses(fulfillment)
    assert_equal %w[returned received_by_seller], order.reload.attributes.values_at("business_status", "return_business_status")
  end

  test "Ozon cancelled posting handed to delivery without a return is expected back" do
    order = ledger_order(platform: "ozon", status: "cancelled", source_status: "cancelled",
      source_substatus: "posting_canceled")
    fulfillment = order.fulfillments.first
    RawOzon::PostingFbs.create!(
      account: @ozon_account, posting_number: fulfillment.external_fulfillment_id, status: "cancelled",
      substatus: "posting_canceled", delivering_date: 2.days.ago, raw_json: {}, created_at: Time.current
    )

    Ec::FulfillmentBusinessStatus::Updater.call(fulfillment)

    assert_equal %w[cancelled expected], statuses(fulfillment)
  end

  test "Ozon cancelled posting that never left stays without a return" do
    order = ledger_order(platform: "ozon", status: "cancelled", source_status: "cancelled",
      source_substatus: "posting_canceled")
    fulfillment = order.fulfillments.first
    RawOzon::PostingFbs.create!(
      account: @ozon_account, posting_number: fulfillment.external_fulfillment_id, status: "cancelled",
      substatus: "posting_canceled", delivering_date: nil, raw_json: {}, created_at: Time.current
    )

    Ec::FulfillmentBusinessStatus::Updater.call(fulfillment)

    assert_equal %w[cancelled none], statuses(fulfillment)
  end

  test "WB cancelled order is expected back when the raw order supplier status is complete" do
    order = ledger_order(platform: "wb", status: "cancelled", source_status: "canceled_by_client",
      source_substatus: "cancelled")
    raw_order = RawWb::Order.create!(
      account: @wb_account, wb_order_id: 70_000_000_000 + @token.to_i(16), nm_id: @wb_product.product_id.to_i,
      delivery_type: "fbs", wb_status: "canceled_by_client", supplier_status: "complete"
    )
    Ec::OrderSourceLink.create!(
      order: order, platform: "wb", source_type: "RawWb::Order", source_id: raw_order.id,
      source_role: "primary", source_key: raw_order.wb_order_id.to_s
    )

    Ec::FulfillmentBusinessStatus::Updater.call(order.fulfillments.first)

    assert_equal %w[cancelled expected], statuses(order.fulfillments.first)
  end

  test "WB order stuck in waiting new with a statistics sale is delivered" do
    order = ledger_order(platform: "wb", status: "processing", source_status: "waiting", source_substatus: "new")
    stats_order = RawWb::StatsOrder.create!(
      account: @wb_account, srid: "SRID-#{@token}", g_number: "G-#{@token}", nm_id: @wb_product.product_id.to_i,
      order_date: 3.days.ago, last_change_date: 1.day.ago, is_cancel: false, synced_at: Time.current
    )
    Ec::OrderSourceLink.create!(
      order: order, platform: "wb", source_type: "RawWb::StatsOrder", source_id: stats_order.id,
      source_role: "primary", source_key: stats_order.srid
    )
    RawWb::StatsSale.create!(
      account: @wb_account, sale_id: "S#{@token}", srid: stats_order.srid, g_number: stats_order.g_number,
      sale_date: 1.day.ago, is_storno: false, synced_at: Time.current
    )

    assert_equal({ order.id => "sale" }, Ec::FulfillmentBusinessStatus::WbStatsEvidence.for_orders([ order.id ]))
    Ec::FulfillmentBusinessStatus::Updater.call(order.fulfillments.first)

    assert_equal %w[delivered none], statuses(order.fulfillments.first)
  end

  test "statistics evidence prefers return over cancel over sale" do
    order = ledger_order(platform: "wb", status: "processing", source_status: "waiting", source_substatus: "new")
    stats_order = RawWb::StatsOrder.create!(
      account: @wb_account, srid: "SRID-#{@token}", g_number: "G-#{@token}", nm_id: @wb_product.product_id.to_i,
      order_date: 3.days.ago, last_change_date: 1.day.ago, is_cancel: true, synced_at: Time.current
    )
    Ec::OrderSourceLink.create!(
      order: order, platform: "wb", source_type: "RawWb::StatsOrder", source_id: stats_order.id,
      source_role: "primary", source_key: stats_order.srid
    )
    assert_equal "cancel", Ec::FulfillmentBusinessStatus::WbStatsEvidence.for_orders([ order.id ])[order.id]

    RawWb::StatsSale.create!(
      account: @wb_account, sale_id: "R#{@token}", srid: stats_order.srid, g_number: stats_order.g_number,
      sale_date: 1.day.ago, is_storno: false, synced_at: Time.current
    )
    assert_equal "return", Ec::FulfillmentBusinessStatus::WbStatsEvidence.for_orders([ order.id ])[order.id]
  end

  test "statistics evidence ignores blank keys and does not borrow another order's sale" do
    order_a = ledger_order(platform: "wb", status: "processing", source_status: "waiting", source_substatus: "new")
    order_b = ledger_order(platform: "wb", status: "processing", source_status: "waiting", source_substatus: "new")
    stats_orders = [ order_a, order_b ].each_with_index.map do |order, index|
      stats_order = RawWb::StatsOrder.create!(
        account: @wb_account, srid: "SRID-#{index}-#{@token}", g_number: nil, nm_id: @wb_product.product_id.to_i,
        order_date: 3.days.ago, last_change_date: 1.day.ago, is_cancel: false, synced_at: Time.current
      )
      Ec::OrderSourceLink.create!(
        order: order, platform: "wb", source_type: "RawWb::StatsOrder", source_id: stats_order.id,
        source_role: "primary", source_key: stats_order.srid
      )
      stats_order
    end
    RawWb::StatsSale.create!(
      account: @wb_account, sale_id: "S#{@token}", srid: stats_orders.last.srid, g_number: nil,
      sale_date: 1.day.ago, is_storno: false, synced_at: Time.current
    )

    evidence = Ec::FulfillmentBusinessStatus::WbStatsEvidence.for_orders([ order_a.id, order_b.id ])

    assert_equal({ order_a.id => "order_only", order_b.id => "sale" }, evidence)
  end

  test "return attaches through the order item first, then the posting number, then a sole fulfillment" do
    order = ledger_order(platform: "ozon", status: "delivered", source_status: "delivered",
      source_substatus: "posting_received")
    second = order.fulfillments.create!(
      platform: "ozon", store: @ozon_store, external_fulfillment_id: "POSTING-2-#{@token}",
      fulfillment_key: "ozon:#{@ozon_store.id}:POSTING-2-#{@token}", fulfillment_type: "fbo", status: "delivered",
      source_status: "delivered", source_substatus: "posting_received"
    )
    second_item = order.items.create!(
      fulfillment: second, platform: "ozon", store: @ozon_store, external_item_id: "ITEM-2-#{@token}",
      platform_sku_id: @ozon_product.platform_sku_id, quantity: 1
    )
    record = ledger_return(order, source_status: "ReceivedBySeller")
    record.items.first.update!(order_item: second_item)

    Ec::FulfillmentBusinessStatus::Updater.for_order(order)

    assert_equal %w[delivered none], statuses(order.fulfillments.find_by!(fulfillment_type: "fbs"))
    assert_equal %w[returned received_by_seller], statuses(second)
  end

  test "return attaches through the posting number when it has no order item link" do
    order = ledger_order(platform: "ozon", status: "delivered", source_status: "delivered",
      source_substatus: "posting_received")
    second = order.fulfillments.create!(
      platform: "ozon", store: @ozon_store, external_fulfillment_id: "POSTING-2-#{@token}",
      fulfillment_key: "ozon:#{@ozon_store.id}:POSTING-2-#{@token}", fulfillment_type: "fbo", status: "delivered",
      source_status: "delivered", source_substatus: "posting_received"
    )
    record = ledger_return(order, source_status: "ReceivedBySeller")
    record.update!(external_posting_number: second.external_fulfillment_id)

    Ec::FulfillmentBusinessStatus::Updater.for_order(order)

    assert_equal %w[delivered none], statuses(order.fulfillments.find_by!(fulfillment_type: "fbs"))
    assert_equal %w[returned received_by_seller], statuses(second)
  end

  test "return with an order item link ignores a conflicting posting number" do
    order = ledger_order(platform: "ozon", status: "delivered", source_status: "delivered",
      source_substatus: "posting_received")
    first = order.fulfillments.find_by!(fulfillment_type: "fbs")
    second = order.fulfillments.create!(
      platform: "ozon", store: @ozon_store, external_fulfillment_id: "POSTING-2-#{@token}",
      fulfillment_key: "ozon:#{@ozon_store.id}:POSTING-2-#{@token}", fulfillment_type: "fbo", status: "delivered",
      source_status: "delivered", source_substatus: "posting_received"
    )
    second_item = order.items.create!(
      fulfillment: second, platform: "ozon", store: @ozon_store, external_item_id: "ITEM-2-#{@token}",
      platform_sku_id: @ozon_product.platform_sku_id, quantity: 1
    )
    record = ledger_return(order, source_status: "ReceivedBySeller")
    record.update!(external_posting_number: first.external_fulfillment_id)
    record.items.first.update!(order_item: second_item)

    Ec::FulfillmentBusinessStatus::Updater.for_order(order)

    assert_equal %w[delivered none], statuses(first)
    assert_equal %w[returned received_by_seller], statuses(second)
  end

  test "order summary shows the least finished fulfillment and the most unresolved return" do
    order = ledger_order(platform: "ozon", status: "delivered", source_status: "delivered",
      source_substatus: "posting_received")
    order.fulfillments.create!(
      platform: "ozon", store: @ozon_store, external_fulfillment_id: "POSTING-3-#{@token}",
      fulfillment_key: "ozon:#{@ozon_store.id}:POSTING-3-#{@token}", fulfillment_type: "fbs", status: "processing",
      source_status: "awaiting_packaging", source_substatus: "posting_created"
    )

    Ec::FulfillmentBusinessStatus::Updater.for_order(order)

    assert_equal %w[awaiting_assembly none], order.reload.attributes.values_at("business_status", "return_business_status")
  end

  test "order summary surfaces a returned posting over a delivered one but behind unfinished ones" do
    order = ledger_order(platform: "ozon", status: "delivered", source_status: "delivered",
      source_substatus: "posting_received")
    returned_posting = order.fulfillments.first
    delivered_posting = order.fulfillments.create!(
      platform: "ozon", store: @ozon_store, external_fulfillment_id: "POSTING-4-#{@token}",
      fulfillment_key: "ozon:#{@ozon_store.id}:POSTING-4-#{@token}", fulfillment_type: "fbs", status: "delivered",
      source_status: "delivered", source_substatus: "posting_received"
    )
    ledger_return(order, source_status: "ReturnedToOzon").tap do |record|
      record.update!(external_posting_number: returned_posting.external_fulfillment_id)
    end

    Ec::FulfillmentBusinessStatus::Updater.for_order(order)

    assert_equal %w[returned at_platform_side], statuses(returned_posting)
    assert_equal %w[delivered none], statuses(delivered_posting)
    assert_equal %w[returned at_platform_side],
      order.reload.attributes.values_at("business_status", "return_business_status")

    delivered_posting.update_columns(source_status: "delivering", source_substatus: "posting_on_way_to_city")
    Ec::FulfillmentBusinessStatus::Updater.for_order(order)

    assert_equal %w[in_delivery at_platform_side],
      order.reload.attributes.values_at("business_status", "return_business_status")
  end

  test "Ozon delivered posting with only a voided return stays delivered without a physical return" do
    order = ledger_order(platform: "ozon", status: "delivered", source_status: "delivered",
      source_substatus: "posting_received")
    ledger_return(order, source_status: "Cancelled")
    fulfillment = order.fulfillments.first

    Ec::FulfillmentBusinessStatus::Updater.call(fulfillment)

    assert_equal %w[delivered no_physical_return], statuses(fulfillment)
    assert_equal %w[delivered no_physical_return],
      order.reload.attributes.values_at("business_status", "return_business_status")
  end

  test "WB delivered order with a statistics return flow is returned" do
    order = ledger_order(platform: "wb", status: "delivered", source_status: "sold", source_substatus: "complete")
    stats_order = RawWb::StatsOrder.create!(
      account: @wb_account, srid: "SRID-#{@token}", g_number: "G-#{@token}", nm_id: @wb_product.product_id.to_i,
      order_date: 3.days.ago, last_change_date: 1.day.ago, is_cancel: false, synced_at: Time.current
    )
    Ec::OrderSourceLink.create!(
      order: order, platform: "wb", source_type: "RawWb::StatsOrder", source_id: stats_order.id,
      source_role: "primary", source_key: stats_order.srid
    )
    RawWb::StatsSale.create!(
      account: @wb_account, sale_id: "R#{@token}", srid: stats_order.srid, g_number: stats_order.g_number,
      sale_date: 1.day.ago, is_storno: false, synced_at: Time.current
    )

    assert_equal "return", Ec::FulfillmentBusinessStatus::WbStatsEvidence.for_orders([ order.id ])[order.id]
    Ec::FulfillmentBusinessStatus::Updater.call(order.fulfillments.first)

    assert_equal %w[returned at_platform_side], statuses(order.fulfillments.first)
  end

  test "write false computes without touching the database" do
    order = ledger_order(platform: "ozon", status: "delivered", source_status: "delivered",
      source_substatus: "posting_received")
    fulfillment = order.fulfillments.first

    result = Ec::FulfillmentBusinessStatus::Updater.call(fulfillment, write: false)

    assert_equal "delivered", result.business_status
    assert_equal %w[needs_review none], statuses(fulfillment)
  end
end
