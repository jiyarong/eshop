require "test_helper"
require_relative "../../../support/book_ledger_fixtures"

class Ec::Inventory::BookLedgerTest < ActiveSupport::TestCase
  include BookLedgerFixtures

  setup { setup_ledger_world }
  teardown { teardown_ledger_world }

  test "exposes the date the ledger rules took effect" do
    assert_kind_of Date, Ec::Inventory::BookLedger::EFFECTIVE_ON
  end

  test "splits received batches into purchase and adjustment and ignores stocktake and unreceived batches" do
    ledger_batch(30)
    ledger_batch(-4, type: :wb_fbw_offset)
    ledger_batch(-5, type: :physical_stocktake_adjustment)
    ledger_batch(10, status: "ordered")

    entry = ledger_entry

    assert_equal 30, entry[:purchase_quantity]
    assert_equal(-4, entry[:adjustment_quantity])
    assert_equal 26, entry[:received_quantity]
    assert_equal 26, entry[:ledger_total]
  end

  test "only counts batches received on or before as_of" do
    ledger_batch(10, received_on: Date.new(2026, 9, 1))
    ledger_batch(7, received_on: Date.new(2026, 9, 20))

    entry = ledger_entry(as_of: Time.zone.parse("2026-09-15 23:59:59"))

    assert_equal 10, entry[:received_quantity]
  end

  test "composes platform side, own side and sellable from a ledger entry" do
    entry = {
      ledger_total: 20, return_in_transit_quantity: 3, return_at_platform_quantity: 2, unsellable_quantity: 1
    }

    composed = Ec::Inventory::BookLedger.compose(entry, platform_sellable: 6, platform_inbound: 2)

    assert_equal 8, composed[:platform_side]
    assert_equal 12, composed[:own_side]
    assert_equal 12, composed[:sellable]
    assert_equal 6, composed[:platform_sellable]
    assert_equal 2, composed[:platform_inbound]
  end

  test "counts every fulfillment type and excludes cancelled, WB returned and stale open orders" do
    ledger_batch(100)
    ledger_order(platform: "wb", status: "delivered", quantity: 7)
    ledger_order(platform: "wb", status: "delivered", quantity: 5, fulfillment_type: "fbw")
    ledger_order(platform: "ozon", status: "delivered", quantity: 9)
    ledger_order(platform: "ozon", status: "shipped", quantity: 2, fulfillment_type: "fbo")
    ledger_order(platform: "wb", status: "cancelled", quantity: 4)
    ledger_order(platform: "wb", status: "returned", quantity: 3)
    ledger_order(platform: "ozon", status: "returned", quantity: 6)
    ledger_order(platform: "wb", status: "processing", quantity: 8, ordered_at: Time.current - 60.days)
    ledger_order(platform: "wb", status: "processing", quantity: 1, ordered_at: Time.current - 5.days)

    entry = ledger_entry

    assert_equal 30, entry[:gross_sales_quantity]
    assert_equal 8, entry[:stale_open_order_quantity]
    assert_equal 70, entry[:ledger_total]

    wb = entry[:by_store][[ "wb", @wb_store.id ]]
    ozon = entry[:by_store][[ "ozon", @ozon_store.id ]]
    assert_equal 13, wb[:gross_sales_quantity]
    assert_equal 12, wb[:status_counts]["signed"]
    assert_equal 1, wb[:status_counts]["processing"]
    assert_equal 17, ozon[:gross_sales_quantity]
    assert_equal 9, ozon[:status_counts]["signed"]
    assert_equal 2, ozon[:status_counts]["shipping"]
  end

  test "uses the fulfillment status over the order level status" do
    ledger_batch(100)
    ledger_order(platform: "ozon", status: "cancelled", fulfillment_status: "delivered", quantity: 3)
    ledger_order(platform: "ozon", status: "delivered", fulfillment_status: "cancelled", quantity: 2)

    entry = ledger_entry

    assert_equal 3, entry[:gross_sales_quantity]
    assert_equal 97, entry[:ledger_total]
  end

  test "falls back to the order status when an item has no fulfillment" do
    ledger_batch(100)
    ledger_order(platform: "wb", status: "returned", quantity: 2, with_fulfillment: false)
    ledger_order(platform: "wb", status: "delivered", quantity: 4, with_fulfillment: false)

    assert_equal 4, ledger_entry[:gross_sales_quantity]
  end

  test "only counts orders placed on or before as_of" do
    ledger_batch(100)
    ledger_order(platform: "wb", status: "delivered", quantity: 3, ordered_at: Time.zone.parse("2026-09-01 10:00:00"))
    ledger_order(platform: "wb", status: "delivered", quantity: 5, ordered_at: Time.zone.parse("2026-09-20 10:00:00"))

    entry = ledger_entry(as_of: Time.zone.parse("2026-09-15 23:59:59"))

    assert_equal 3, entry[:gross_sales_quantity]
  end

  test "reverses sold items by the status of linked returns and buckets where the goods are" do
    ledger_batch(100)
    received = ledger_order(platform: "ozon", status: "delivered", quantity: 3)
    ledger_return(received, source_status: "ReceivedBySeller", quantity: 2)
    at_platform = ledger_order(platform: "ozon", status: "delivered")
    ledger_return(at_platform, source_status: "ReturnedToOzon")
    moving = ledger_order(platform: "ozon", status: "delivered")
    ledger_return(moving, source_status: "MovingToSeller")
    refunded = ledger_order(platform: "ozon", status: "delivered")
    ledger_return(refunded, source_status: "MoneyReturned")
    rejected = ledger_order(platform: "ozon", status: "delivered")
    ledger_return(rejected, source_status: "Rejected")

    entry = ledger_entry

    assert_equal 7, entry[:gross_sales_quantity]
    assert_equal 4, entry[:reversed_quantity]
    assert_equal 97, entry[:ledger_total]
    assert_equal 1, entry[:return_at_platform_quantity]
    assert_equal 1, entry[:return_in_transit_quantity]
    assert_equal 0, entry[:unsellable_quantity]
    assert_equal 4, entry[:by_store][[ "ozon", @ozon_store.id ]][:reversed_quantity]
  end

  test "never reverses more than the sold quantity" do
    ledger_batch(100)
    order = ledger_order(platform: "ozon", status: "delivered", quantity: 1)
    ledger_return(order, source_status: "ReceivedBySeller", quantity: 5)

    entry = ledger_entry

    assert_equal 1, entry[:reversed_quantity]
    assert_equal 100, entry[:ledger_total]
  end

  test "classifies reversed goods as unsellable by Ozon reason and WB return type" do
    ledger_batch(100)
    ozon = ledger_order(platform: "ozon", status: "delivered")
    ledger_return(ozon, source_status: "ReceivedBySeller", reason: "Товар не работает / брак")
    wb = ledger_order(platform: "wb", status: "delivered")
    ledger_return(wb, source_status: "Выдано", payload: { "return_type" => "Возврат брака" })
    sellable = ledger_order(platform: "ozon", status: "delivered")
    ledger_return(sellable, source_status: "ReceivedBySeller", reason: "Покупатель передумал")

    entry = ledger_entry

    assert_equal 3, entry[:reversed_quantity]
    assert_equal 2, entry[:unsellable_quantity]
    assert_equal 100, entry[:ledger_total]
  end

  test "buckets goods of cancelled orders that already left the warehouse" do
    ledger_batch(100)
    # WB handed over for delivery (supplier status complete), no return yet -> on its way back.
    ledger_order(platform: "wb", status: "cancelled", quantity: 2, source_substatus: "complete")
    # WB cancelled before dispatch -> never left, no bucket.
    ledger_order(platform: "wb", status: "cancelled", quantity: 1, source_substatus: "cancel")
    # Fulfillment substatus reads cancelled but the raw WB order is complete.
    stale_substatus = ledger_order(platform: "wb", status: "cancelled", quantity: 1, source_substatus: "cancelled")
    raw_order = RawWb::Order.create!(
      account: @wb_account, wb_order_id: 70_000_000_000 + @token.to_i(16), nm_id: 1,
      delivery_type: "fbs", wb_status: "canceled_by_client", supplier_status: "complete"
    )
    Ec::OrderSourceLink.create!(
      order: stale_substatus, platform: "wb", source_type: "RawWb::Order", source_id: raw_order.id,
      source_role: "primary", source_key: raw_order.wb_order_id.to_s
    )
    # Ozon with a delivery transfer time -> on its way back; without -> never left.
    handed_over = ledger_order(platform: "ozon", status: "cancelled")
    RawOzon::PostingFbs.create!(
      account: @ozon_account, posting_number: handed_over.items.first.external_item_id, status: "cancelled",
      delivering_date: Time.current - 3.days, raw_json: {}, created_at: Time.current
    )
    ledger_order(platform: "ozon", status: "cancelled")
    # WB defect cancelled after dispatch, no return yet -> unsellable.
    ledger_order(platform: "wb", status: "cancelled", source_status: "defect", source_substatus: "complete")
    # WB cancelled after dispatch and already issued back -> own side, no bucket.
    back = ledger_order(platform: "wb", status: "cancelled", source_substatus: "complete")
    ledger_return(back, source_status: "Выдано")
    # WB defect order issued back with an ordinary return type -> still unsellable (raw status defect).
    defect_back = ledger_order(platform: "wb", status: "cancelled", source_status: "defect", source_substatus: "complete")
    ledger_return(defect_back, source_status: "Выдано", payload: { "return_type" => "Возврат товара, который приехал по МП, продавцу" })

    entry = ledger_entry

    assert_equal 4, entry[:return_in_transit_quantity]
    assert_equal 2, entry[:unsellable_quantity]
    assert_equal 0, entry[:return_at_platform_quantity]
    assert_equal 0, entry[:gross_sales_quantity]
    assert_equal 0, entry[:reversed_quantity]
    assert_equal 100, entry[:ledger_total]
  end

  test "matches a return to the posting it names so another delivered posting is not reversed" do
    ledger_batch(100)
    order = ledger_order(platform: "ozon", status: "delivered")
    cancelled_posting = add_ozon_posting(order, status: "cancelled", delivering_date: Time.current - 3.days)
    returned = ledger_return(order, source_status: "ReceivedBySeller")
    returned.update!(external_posting_number: cancelled_posting)

    entry = ledger_entry

    assert_equal 1, entry[:gross_sales_quantity]
    assert_equal 0, entry[:reversed_quantity]
    assert_equal 99, entry[:ledger_total]
    assert_equal 0, entry[:return_in_transit_quantity]
  end

  test "buckets a posting scoped return in transit without reversing the delivered posting" do
    ledger_batch(100)
    order = ledger_order(platform: "ozon", status: "delivered")
    cancelled_posting = add_ozon_posting(order, status: "cancelled", delivering_date: Time.current - 3.days)
    returned = ledger_return(order, source_status: "MovingToSeller")
    returned.update!(external_posting_number: cancelled_posting)

    entry = ledger_entry

    assert_equal 1, entry[:gross_sales_quantity]
    assert_equal 0, entry[:reversed_quantity]
    assert_equal 99, entry[:ledger_total]
    assert_equal 1, entry[:return_in_transit_quantity]
  end

  test "falls back to order level allocation when the return posting matches no item" do
    ledger_batch(100)
    order = ledger_order(platform: "ozon", status: "delivered")
    returned = ledger_return(order, source_status: "ReceivedBySeller")
    returned.update!(external_posting_number: "UNKNOWN-#{@token}")

    entry = ledger_entry

    assert_equal 1, entry[:reversed_quantity]
    assert_equal 100, entry[:ledger_total]
  end

  test "ignores returns that happened after as_of" do
    ledger_batch(100)
    order = ledger_order(platform: "ozon", status: "delivered", quantity: 2, ordered_at: Time.current - 40.days)
    ledger_return(order, source_status: "ReceivedBySeller").update!(requested_at: Time.current - 10.days)

    assert_equal 0, ledger_entry(as_of: Time.current - 30.days)[:reversed_quantity]
    assert_equal 1, ledger_entry[:reversed_quantity]
  end

  test "attributes a return item without a sku product to the only SKU of the order" do
    ledger_batch(100)
    order = ledger_order(platform: "ozon", status: "delivered")
    ledger_return(order, source_status: "ReceivedBySeller").items.update_all(sku_product_id: nil)

    entry = ledger_entry

    assert_equal 1, entry[:reversed_quantity]
    assert_equal 100, entry[:ledger_total]
  end

  test "ignores a return item without a sku product when the order spans several SKUs" do
    other_sku = Ec::Sku.create!(sku_code: "LEDGER-OTHER-#{@token}", product_name: "Other #{@token}")
    other_product = Ec::SkuProduct.create!(
      sku_code: other_sku.sku_code, store: @ozon_store, product_id: "OZO-#{@token}",
      platform_sku_id: "8#{@token.to_i(16) % 100_000_000}", offer_id: "OFFER-O-#{@token}"
    )
    ledger_batch(100)
    order = ledger_order(platform: "ozon", status: "delivered")
    order.items.create!(
      fulfillment: order.fulfillments.first, platform: "ozon", store: @ozon_store,
      external_item_id: "OTHER-#{@token}", platform_sku_id: other_product.platform_sku_id, quantity: 1
    )
    ledger_return(order, source_status: "ReceivedBySeller").items.update_all(sku_product_id: nil)

    entry = ledger_entry

    assert_equal 1, entry[:gross_sales_quantity]
    assert_equal 0, entry[:reversed_quantity]
  ensure
    if other_product
      Ec::OrderItem.where(store_id: @ozon_store.id).delete_all
      Ec::OperationAction.where(ec_sku_id: other_sku.id).delete_all
      Ec::SkuProduct.where(id: other_product.id).delete_all
      Ec::OperationLog.where(record_type: "Ec::SkuProduct", record_id: other_product.id).delete_all
    end
    if other_sku
      Ec::Sku.with_deleted.where(id: other_sku.id).delete_all
      Ec::OperationLog.where(record_type: "Ec::Sku", record_id: other_sku.id).delete_all
    end
  end

  test "does not treat an Ozon delivering date after as_of as a dispatch signal" do
    ledger_batch(100)
    cancelled = ledger_order(platform: "ozon", status: "cancelled", ordered_at: Time.current - 40.days)
    RawOzon::PostingFbs.create!(
      account: @ozon_account, posting_number: cancelled.items.first.external_item_id, status: "cancelled",
      delivering_date: Time.current - 5.days, raw_json: {}, created_at: Time.current
    )

    assert_equal 0, ledger_entry(as_of: Time.current - 30.days)[:return_in_transit_quantity]
    assert_equal 1, ledger_entry[:return_in_transit_quantity]
  end

  test "lists non-cancelled sales that match no SKU product" do
    unknown_id = "UNKNOWN-#{@token}"
    ledger_order(platform: "ozon", status: "delivered", quantity: 4, platform_sku_id: unknown_id)
    ledger_order(platform: "ozon", status: "cancelled", quantity: 9, platform_sku_id: unknown_id)
    ledger_order(platform: "ozon", status: "delivered", quantity: 2)

    rows = Ec::Inventory::BookLedger.unattributed.select { |row| row[:platform_sku_id] == unknown_id }

    assert_equal [ { platform: "ozon", platform_sku_id: unknown_id, quantity: 4 } ], rows
    assert_equal 0, Ec::Inventory::BookLedger.unattributed.count { |row| row[:platform_sku_id] == @ozon_product.platform_sku_id }
  end

  private

  # Adds a second posting (fulfillment plus item of the SKU) to an Ozon order; returns its posting number.
  def add_ozon_posting(order, status:, delivering_date: nil, quantity: 1)
    key = "ozon-#{SecureRandom.hex(6)}"
    fulfillment = order.fulfillments.create!(
      platform: "ozon", store: @ozon_store, external_fulfillment_id: key,
      fulfillment_key: "ozon:#{@ozon_store.id}:#{key}", fulfillment_type: "fbs", status: status
    )
    order.items.create!(
      fulfillment: fulfillment, platform: "ozon", store: @ozon_store, external_item_id: key,
      platform_sku_id: @ozon_product.platform_sku_id, quantity: quantity
    )
    if delivering_date
      RawOzon::PostingFbs.create!(
        account: @ozon_account, posting_number: key, status: status,
        delivering_date: delivering_date, raw_json: {}, created_at: Time.current
      )
    end
    key
  end
end
