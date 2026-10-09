require "test_helper"

class EcOrderImportWbPriceBackfillTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(4).upcase
    @account = RawWb::SellerAccount.create!(name: "WB backfill #{@token}", api_token: "wb-token-#{@token}", company_type: "small")
    @store = Ec::Store.create!(platform: "wb", store_name: "WB backfill #{@token}", company_type: "general", wb_raw_account_id: @account.id)
    @ozon_store = Ec::Store.create!(platform: "ozon", store_name: "Ozon backfill #{@token}", company_type: "general")
    @orders = []
  end

  teardown do
    Ec::OrderItem.where(order_id: @orders.map(&:id)).delete_all
    Ec::Order.where(id: @orders.map(&:id)).delete_all
    RawWb::StatsOrder.where(account_id: @account.id).delete_all
    Ec::OperationLog.where(record_type: "Ec::Store", record_id: [@store.id, @ozon_store.id]).delete_all
    @store.destroy
    @ozon_store.destroy
    @account.destroy
  end

  test "replaces legacy buyer-side prices with the stats commission base and buyer paid price" do
    item = legacy_item("matched", unit_price: 40.57, currency: "BYN")
    stats(item, price_with_disc: 1449.93, finished_price: 1131.01, synced_at: Time.utc(2026, 10, 8, 3))

    result = Ec::OrderImport::WbPriceBackfill.call(dry_run: false)

    item.reload
    assert_equal BigDecimal("1449.93"), item.unit_price
    assert_equal "RUB", item.currency_code
    assert_equal BigDecimal("1131.01"), item.buyer_paid_unit_price
    assert_equal "RUB", item.buyer_currency_code
    assert_equal Time.utc(2026, 10, 8, 3), item.buyer_paid_synced_at
    assert_equal 1, result[:updated]
  end

  test "treats zero stats prices as unknown" do
    item = legacy_item("zero", unit_price: 40.57, currency: "BYN", buyer_paid: 999, buyer_currency: "RUB")
    stats(item, price_with_disc: 0, finished_price: 0)

    Ec::OrderImport::WbPriceBackfill.call(dry_run: false)

    item.reload
    assert_nil item.unit_price
    assert_nil item.currency_code
    assert_nil item.buyer_paid_unit_price
    assert_nil item.buyer_currency_code
  end

  test "clears the legacy price of items that have no stats order" do
    item = legacy_item("unmatched", unit_price: 40.57, currency: "BYN")

    result = Ec::OrderImport::WbPriceBackfill.call(dry_run: false)

    assert_nil item.reload.unit_price
    assert_nil item.currency_code
    assert_equal 1, result[:cleared]
  end

  test "keeps the legacy price of unmatched items when clearing is disabled" do
    item = legacy_item("kept", unit_price: 40.57, currency: "BYN")

    Ec::OrderImport::WbPriceBackfill.call(dry_run: false, clear_unmatched: false)

    assert_equal BigDecimal("40.57"), item.reload.unit_price
  end

  test "defaults to a dry run that reports counts without writing" do
    matched = legacy_item("dry-matched", unit_price: 40.57, currency: "BYN")
    stats(matched, price_with_disc: 1449.93, finished_price: 1131.01)
    unmatched = legacy_item("dry-unmatched", unit_price: 41, currency: "BYN")

    result = Ec::OrderImport::WbPriceBackfill.call

    assert_equal({ updated: 1, cleared: 1 }, result)
    assert_equal BigDecimal("40.57"), matched.reload.unit_price
    assert_equal BigDecimal("41"), unmatched.reload.unit_price
  end

  test "is idempotent and never touches other platforms" do
    item = legacy_item("idempotent", unit_price: 40.57, currency: "BYN")
    stats(item, price_with_disc: 1449.93, finished_price: 1131.01)
    ozon_item = ozon_order_item(unit_price: 2400)

    first = Ec::OrderImport::WbPriceBackfill.call(dry_run: false)
    second = Ec::OrderImport::WbPriceBackfill.call(dry_run: false)

    assert_equal 1, first[:updated]
    assert_equal({ updated: 0, cleared: 0 }, second)
    assert_equal BigDecimal("2400"), ozon_item.reload.unit_price
    assert_equal "RUB", ozon_item.currency_code
  end

  private

  def legacy_item(key, unit_price:, currency:, buyer_paid: nil, buyer_currency: nil)
    order = Ec::Order.create!(
      platform: "wb", store: @store, order_key: "wb:#{@store.id}:#{@token}-#{key}", external_order_id: "SRID-#{@token}-#{key}",
      order_status: "shipped", ordered_at: Time.utc(2026, 10, 7, 12)
    )
    @orders << order
    order.items.create!(
      platform: "wb", store: @store, platform_sku_id: "1250676828", quantity: 1,
      unit_price: unit_price, currency_code: currency,
      buyer_paid_unit_price: buyer_paid, buyer_currency_code: buyer_currency
    )
  end

  def stats(item, price_with_disc:, finished_price:, synced_at: Time.utc(2026, 10, 8, 3))
    RawWb::StatsOrder.create!(
      account: @account, srid: item.order.external_order_id, order_date: item.order.ordered_at, nm_id: 1_250_676_828,
      total_price: 5000, price_with_disc: price_with_disc, finished_price: finished_price, synced_at: synced_at
    )
  end

  def ozon_order_item(unit_price:)
    order = Ec::Order.create!(
      platform: "ozon", store: @ozon_store, order_key: "ozon:#{@ozon_store.id}:#{@token}", external_order_id: "OZ-#{@token}",
      order_status: "delivered", ordered_at: Time.utc(2026, 10, 7, 12)
    )
    @orders << order
    order.items.create!(platform: "ozon", store: @ozon_store, platform_sku_id: "1", quantity: 1, unit_price: unit_price, currency_code: "RUB")
  end
end
