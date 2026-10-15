require "test_helper"

class EcOrderIdentifiersTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(4).upcase
    @account = RawOzon::SellerAccount.create!(
      client_id: "ids-ozon-#{@token}", api_key: "key-#{@token}", company_type: "general", raw_json: {}
    )
    @store = Ec::Store.create!(
      platform: "ozon", store_name: "编号店 #{@token}", company_type: "general", ozon_raw_account_id: @account.id
    )
    @order = Ec::Order.create!(
      platform: "ozon", store: @store, external_order_id: "OZ-ORDER-#{@token}",
      external_order_number: "OZ-NUMBER-#{@token}", order_key: "ozon:#{@store.id}:OZ-NUMBER-#{@token}",
      order_status: "delivered", ordered_at: Time.zone.parse("2026-06-02 03:54:10"), synced_at: Time.zone.now
    )
    @fulfillment = @order.fulfillments.create!(
      platform: "ozon", store: @store, external_fulfillment_id: "OZ-NUMBER-#{@token}-1",
      fulfillment_key: "ozon:#{@store.id}:OZ-NUMBER-#{@token}-1", fulfillment_type: "fbs", status: "delivered",
      tracking_number: "TRACK-#{@token}", synced_at: Time.zone.now
    )
    @ozon_order_id = 39_000_000_000 + @token.hex
    @posting = RawOzon::PostingFbs.create!(
      account: @account, posting_number: "OZ-NUMBER-#{@token}-1", order_id: @ozon_order_id,
      order_number: "OZ-NUMBER-#{@token}", status: "delivered", tracking_number: "TRACK-#{@token}",
      raw_json: { "barcodes" => { "upper_barcode" => "ii#{@token}1", "lower_barcode" => "ii#{@token}2" } },
      synced_at: Time.zone.now
    )
    @order.source_links.create!(
      fulfillment: @fulfillment, platform: "ozon", source_type: "RawOzon::PostingFbs", source_id: @posting.id,
      source_key: @posting.posting_number, source_role: "primary", synced_at: Time.zone.now
    )
    @return = Ec::Return.create!(
      platform: "ozon", store: @store, order: @order, return_key: "RET-#{@token}", return_type: "customer_return",
      process_status: "completed", external_return_id: "7001#{@token.hex}", external_posting_number: @posting.posting_number,
      source_status: "ReturnedToOzon", synced_at: Time.zone.now
    )
    @raw_return = RawOzon::Return.create!(
      account: @account, return_id: @return.external_return_id.to_i, return_schema: "Fbs",
      posting_number: @posting.posting_number, quantity: 1,
      raw_json: { "clearing_id" => "CLR-#{@token}", "return_clearing_id" => nil, "logistic" => { "barcode" => "ii#{@token}R" } },
      synced_at: Time.zone.now
    )
    Ec::ReturnSourceLink.create!(
      return_id: @return.id, platform: "ozon", source_type: "RawOzon::Return", source_id: @raw_return.id,
      source_key: @return.external_return_id, synced_at: Time.zone.now
    )
  end

  teardown do
    Ec::ReturnSourceLink.where(return_id: @return&.id).delete_all
    Ec::Return.where(id: @return&.id).delete_all
    RawOzon::Return.where(id: @raw_return&.id).delete_all
    Ec::OrderSourceLink.where(order_id: @order&.id).delete_all
    RawOzon::PostingFbs.where(id: @posting&.id).delete_all
    Ec::OrderFulfillment.where(order_id: @order&.id).delete_all
    Ec::Order.where(id: @order&.id).delete_all
    Ec::Store.where(id: @store&.id).delete_all
    RawOzon::SellerAccount.where(id: @account&.id).delete_all
  end

  test "collects the numbers of the order, its posting and its return, each value once" do
    order = Ec::Order.includes(:fulfillments, :items).find(@order.id)

    entries = Ec::OrderIdentifiers.for_orders([ order ]).fetch(order.id)
    by_key = entries.group_by(&:key).transform_values { |list| list.map(&:value) }

    assert_equal [ "OZ-NUMBER-#{@token}-1" ], by_key.fetch(:posting_number)
    assert_equal [ @ozon_order_id.to_s ], by_key.fetch(:ozon_order_id)
    assert_equal [ "OZ-ORDER-#{@token}" ], by_key.fetch(:platform_order_id)
    assert_equal [ "OZ-NUMBER-#{@token}" ], by_key.fetch(:ozon_order_number)
    assert_equal [ "TRACK-#{@token}" ], by_key.fetch(:tracking_number)
    assert_equal [ "ii#{@token}1", "ii#{@token}2" ], by_key.fetch(:label_barcode)
    assert_equal [ @return.external_return_id ], by_key.fetch(:return_id)
    assert_equal [ "CLR-#{@token}" ], by_key.fetch(:clearing_id)
    assert_equal [ "ii#{@token}R" ], by_key.fetch(:return_barcode)
    assert_equal entries.map(&:value).uniq, entries.map(&:value), "a value must not be listed twice"
    # the generic order number is the same value as the posting's order number: the specific label wins
    assert_not_includes by_key.fetch(:platform_order_number, []), "OZ-NUMBER-#{@token}"
  end

  test "an order without any linked source still lists its own numbers" do
    bare = Ec::Order.create!(
      platform: "ozon", store: @store, external_order_id: "BARE-#{@token}", external_order_number: "BARE-NUM-#{@token}",
      order_key: "ozon:#{@store.id}:BARE-NUM-#{@token}", order_status: "processing", synced_at: Time.zone.now
    )

    entries = Ec::OrderIdentifiers.for_orders([ Ec::Order.includes(:fulfillments, :items).find(bare.id) ]).fetch(bare.id)

    assert_equal [ :platform_order_id, :platform_order_number ], entries.map(&:key)
    assert_equal [ "BARE-#{@token}", "BARE-NUM-#{@token}" ], entries.map(&:value)
  ensure
    Ec::Order.where(id: bare&.id).delete_all
  end

  test "an empty page has no identifiers" do
    assert_equal({}, Ec::OrderIdentifiers.for_orders([]))
  end
end
