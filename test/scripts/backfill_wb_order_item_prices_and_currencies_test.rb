# frozen_string_literal: true

require "test_helper"

ENV["SKIP_WB_ORDER_ITEM_PRICE_CURRENCY_BACKFILL_RUN"] = "1"
load Rails.root.join("script/backfill_wb_order_item_prices_and_currencies.rb")
ENV.delete("SKIP_WB_ORDER_ITEM_PRICE_CURRENCY_BACKFILL_RUN")

class BackfillWbOrderItemPricesAndCurrenciesTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(4).upcase
    @account = RawWb::SellerAccount.create!(
      name: "WB price backfill #{@token}",
      api_token: "wb-price-backfill-#{@token}",
      company_type: "small"
    )
    @store = Ec::Store.create!(
      platform: "wb",
      store_name: "WB price backfill #{@token}",
      company_type: "small",
      wb_raw_account_id: @account.id
    )
    @raw_order = RawWb::Order.create!(
      account: @account,
      wb_order_id: 900_000_000 + @token.to_i(16),
      srid: "WB-PRICE-#{@token}",
      delivery_type: "fbs",
      supplier_status: "confirm",
      wb_status: "waiting",
      price: 789.12,
      converted_price: 123.45,
      currency_code: 398
    )
    @order = Ec::Order.create!(
      platform: "wb",
      store: @store,
      order_key: "wb-price-backfill-#{@token}",
      order_status: "processing"
    )
    @item = Ec::OrderItem.create!(
      order: @order,
      platform: "wb",
      store: @store,
      quantity: 1,
      unit_price: @raw_order.converted_price,
      currency_code: "RUB"
    )
    Ec::OrderSourceLink.create!(
      order: @order,
      platform: "wb",
      source_type: "RawWb::Order",
      source_id: @raw_order.id,
      source_role: "primary"
    )
  end

  teardown do
    Ec::OrderSourceLink.where(order_id: @order&.id).delete_all
    Ec::OrderItem.where(id: @item&.id).delete_all
    Ec::Order.where(id: @order&.id).delete_all
    @raw_order&.destroy
    @store&.destroy
    @account&.destroy
  end

  test "preview reports changes without writing" do
    changes = WbOrderItemPriceCurrencyBackfill.new(apply: false).call

    assert_equal 1, changes.size
    assert_equal BigDecimal("123.45"), @item.reload.unit_price
    assert_equal "RUB", @item.currency_code
  end

  test "apply backfills raw price and currency idempotently" do
    assert_equal 1, WbOrderItemPriceCurrencyBackfill.new(apply: true).call.size
    assert_equal BigDecimal("789.12"), @item.reload.unit_price
    assert_equal "KZT", @item.currency_code
    assert_empty WbOrderItemPriceCurrencyBackfill.new(apply: true).call
  end
end
