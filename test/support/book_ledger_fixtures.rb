require "securerandom"

# Shared data builders for book ledger tests. Include it in a test class and call
# setup_ledger_world in setup / teardown_ledger_world in teardown.
module BookLedgerFixtures
  def setup_ledger_world
    @token = SecureRandom.hex(4).upcase
    @sku = Ec::Sku.create!(sku_code: "LEDGER-#{@token}", product_name: "Ledger #{@token}")
    @wb_account = RawWb::SellerAccount.create!(
      name: "wb-ledger-#{@token}", api_token: "token-#{@token}", company_type: "small"
    )
    @ozon_account = RawOzon::SellerAccount.create!(
      company_name: "ozon-ledger-#{@token}", client_id: "client-#{@token}",
      api_key: "key-#{@token}", company_type: "small"
    )
    @wb_store = Ec::Store.create!(
      platform: "wb", store_name: "WB Ledger #{@token}", company_type: "small",
      wb_raw_account_id: @wb_account.id, is_active: true
    )
    @ozon_store = Ec::Store.create!(
      platform: "ozon", store_name: "Ozon Ledger #{@token}", company_type: "small",
      ozon_raw_account_id: @ozon_account.id, is_active: true
    )
    @wb_product = Ec::SkuProduct.create!(
      sku_code: @sku.sku_code, store: @wb_store, product_id: "NM-#{@token}",
      platform_sku_id: "WBCHRT-#{@token}"
    )
    @ozon_product = Ec::SkuProduct.create!(
      sku_code: @sku.sku_code, store: @ozon_store, product_id: "OZP-#{@token}",
      platform_sku_id: "9#{@token.to_i(16) % 100_000_000}", offer_id: "OFFER-#{@token}"
    )
  end

  def teardown_ledger_world
    store_ids = [ @wb_store&.id, @ozon_store&.id ].compact
    return_ids = Ec::Return.where(store_id: store_ids).select(:id)
    Ec::ReturnSourceLink.where(return_id: return_ids).delete_all
    Ec::ReturnItem.where(return_id: return_ids).delete_all
    Ec::Return.where(store_id: store_ids).delete_all
    Ec::OrderSourceLink.where(order_id: Ec::Order.where(store_id: store_ids).select(:id)).delete_all
    Ec::OrderItem.where(store_id: store_ids).delete_all
    Ec::OrderFulfillment.where(store_id: store_ids).delete_all
    Ec::Order.where(store_id: store_ids).delete_all
    RawWb::Order.where(account_id: @wb_account&.id).delete_all
    RawOzon::PostingFbs.where(account_id: @ozon_account&.id).delete_all
    Ec::SkuInventoryLevel.where(sku_code: @sku&.sku_code).delete_all
    # Normal purchase batches record an Ec::OperationAction against the first SKU product (after_create_commit).
    Ec::OperationAction.where(ec_sku_id: @sku&.id).delete_all
    Ec::SkuBatch.where(sku_code: @sku&.sku_code).delete_all
    Ec::SkuProduct.where(sku_code: @sku&.sku_code).delete_all
    Ec::Store.where(id: store_ids).delete_all
    RawWb::SellerAccount.where(id: @wb_account&.id).delete_all
    RawOzon::SellerAccount.where(id: @ozon_account&.id).delete_all
    Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
  end

  def ledger_batch(quantity, type: :normal, status: "received", received_on: nil)
    attributes = {
      sku_code: @sku.sku_code, batch_code: "B-#{SecureRandom.hex(4)}", status: status, batch_type: type,
      purchased_quantity: quantity, received_quantity: quantity, purchase_unit_price_cny: 1,
      received_on: received_on
    }
    attributes[:defect_offset_note] = "ledger test" unless type.to_s == "normal"
    Ec::SkuBatch.create!(attributes)
  end

  # Creates an order with one fulfillment and one item attributed to @sku.
  def ledger_order(platform:, status:, quantity: 1, fulfillment_type: "fbs", fulfillment_status: nil,
                   ordered_at: Time.current - 5.days, source_status: nil, source_substatus: nil,
                   with_fulfillment: true, platform_sku_id: nil)
    store = platform == "wb" ? @wb_store : @ozon_store
    product_id = platform == "wb" ? @wb_product.product_id : @ozon_product.platform_sku_id
    key = "#{platform}-#{SecureRandom.hex(6)}"
    order = Ec::Order.create!(
      platform: platform, store: store, order_key: key, external_order_id: key,
      order_status: status, ordered_at: ordered_at
    )
    fulfillment = nil
    if with_fulfillment
      fulfillment = order.fulfillments.create!(
        platform: platform, store: store, external_fulfillment_id: key,
        fulfillment_key: "#{platform}:#{store.id}:#{key}", fulfillment_type: fulfillment_type,
        status: fulfillment_status || status, source_status: source_status, source_substatus: source_substatus
      )
    end
    order.items.create!(
      fulfillment: fulfillment, platform: platform, store: store, external_item_id: key,
      platform_sku_id: platform_sku_id || product_id, quantity: quantity
    )
    order
  end

  def ledger_return(order, source_status:, quantity: 1, reason: nil, payload: {})
    product = order.platform == "wb" ? @wb_product : @ozon_product
    key = "RET-#{SecureRandom.hex(6)}"
    record = Ec::Return.create!(
      platform: order.platform, store: order.store, order: order, return_key: key, external_return_id: key,
      return_type: "customer_return", source_status: source_status, source_substatus: reason,
      source_payload: payload
    )
    record.items.create!(
      platform: order.platform, store: order.store, sku_product: product, item_key: key,
      quantity: quantity, restockable: false
    )
    record
  end

  def ledger_entry(as_of: nil)
    Ec::Inventory::BookLedger.call(sku_codes: [ @sku.sku_code ], as_of: as_of).fetch(@sku.sku_code.upcase)
  end
end
