require "test_helper"

module Ec
  class OzonShippedAtTest < ActiveSupport::TestCase
    setup do
      @token = SecureRandom.hex(4).upcase
      @account = RawOzon::SellerAccount.create!(
        client_id: "ozon-shipped-#{@token}", api_key: "test-api-key", company_name: "Ozon shipped #{@token}",
        company_type: "general", raw_json: {}
      )
      @store = Ec::Store.create!(platform: "ozon", store_name: "Ozon shipped #{@token}", company_type: "general", ozon_raw_account_id: @account.id)
      @shipment_deadline = Time.utc(2026, 10, 14, 17, 0, 0)
      @handed_over = Time.utc(2026, 10, 15, 10, 23, 56)
    end

    teardown do
      orders = Ec::Order.where(store_id: @store&.id)
      fulfillments = Ec::OrderFulfillment.where(order_id: orders.select(:id))
      Ec::OrderSourceLink.where(order_id: orders.select(:id)).delete_all
      Ec::OrderItem.where(order_id: orders.select(:id)).delete_all
      fulfillments.delete_all
      orders.delete_all
      RawOzon::PostingItem.where(account_id: @account&.id).delete_all
      RawOzon::PostingFbs.where(account_id: @account&.id).delete_all
      @store&.destroy
      @account&.destroy
    end

    test "FBS shipped_at is the time the posting was handed to delivery, not the shipment deadline" do
      posting = fbs_posting("A", status: "delivering", delivering_date: @handed_over)

      import(posting)

      assert_equal @handed_over, fulfillment_of(posting).shipped_at
    end

    test "a posting cancelled before the hand-over has no shipped_at, one cancelled afterwards keeps it" do
      before = fbs_posting("B", status: "cancelled", delivering_date: nil)
      after = fbs_posting("C", status: "cancelled", delivering_date: @handed_over)

      import(before)
      import(after)

      assert_nil fulfillment_of(before).shipped_at
      assert_equal @handed_over, fulfillment_of(after).shipped_at
    end

    test "shipped_at follows the posting when delivering_date arrives on a later sync" do
      posting = fbs_posting("D", status: "awaiting_deliver", delivering_date: nil)
      import(posting)
      assert_nil fulfillment_of(posting).shipped_at

      posting.update!(status: "delivering", delivering_date: @handed_over)
      import(posting)

      assert_equal @handed_over, fulfillment_of(posting).shipped_at
    end

    test "backfill rewrites shipped_at of existing FBS fulfillments from delivering_date and is idempotent" do
      shipped = fbs_posting("E", status: "delivering", delivering_date: @handed_over)
      cancelled = fbs_posting("F", status: "cancelled", delivering_date: nil)
      [shipped, cancelled].each do |posting|
        import(posting)
        fulfillment_of(posting).update_columns(shipped_at: @shipment_deadline)
      end

      assert_equal 2, Ec::OrderImport::OzonShippedAt.call(account_id: @account.id)

      assert_equal @handed_over, fulfillment_of(shipped).shipped_at
      assert_nil fulfillment_of(cancelled).shipped_at
      assert_equal 0, Ec::OrderImport::OzonShippedAt.call(account_id: @account.id)
    end

    test "backfill leaves non-FBS fulfillments alone" do
      fbo = fbs_posting("G", status: "delivering", delivering_date: @handed_over)
      import(fbo)
      fulfillment = fulfillment_of(fbo)
      fulfillment.update_columns(fulfillment_type: "fbo", shipped_at: nil)

      assert_equal 0, Ec::OrderImport::OzonShippedAt.call(account_id: @account.id)
      assert_nil fulfillment.reload.shipped_at
    end

    private

    def fbs_posting(suffix, status:, delivering_date:)
      number = "OZ-SHIP-#{@token}-#{suffix}"
      posting = RawOzon::PostingFbs.create!(
        account: @account, posting_number: number, order_id: 700_000_000 + @token.to_i(16) + suffix.ord,
        order_number: "ORD-#{number}", status: status, delivery_method_name: "Ozon Rocket",
        analytics_data: {}, financial_data: { "products" => [] }, raw_json: { "posting_number" => number },
        in_process_at: Time.utc(2026, 10, 14, 8, 0, 0), shipment_date: @shipment_deadline,
        delivering_date: delivering_date, created_at: Time.utc(2026, 10, 14, 7, 55, 0),
        synced_at: Time.utc(2026, 10, 15, 11, 0, 0)
      )
      RawOzon::PostingItem.create!(
        account: @account, posting_number: number, posting_type: "fbs", ozon_sku: 4_100_000_000 + @token.to_i(16),
        offer_id: "SHIP-#{suffix}", name: "Item", quantity: 1, price: 100, currency_code: "RUB", raw_json: {}
      )
      posting
    end

    def import(posting)
      Ec::OrderImport::Ozon.new.send(:import_posting, posting, "fbs", "RawOzon::PostingFbs")
    end

    def fulfillment_of(posting)
      Ec::OrderFulfillment.find_by!(platform: "ozon", store: @store, fulfillment_key: "ozon:#{@store.id}:#{posting.posting_number}")
    end
  end
end
