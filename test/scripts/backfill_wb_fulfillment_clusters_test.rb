require "test_helper"

class BackfillWbFulfillmentClustersTest < ActiveSupport::TestCase
  SCRIPT_PATH = Rails.root.join("script/backfill_wb_fulfillment_clusters.rb")

  setup do
    @token = SecureRandom.hex(4).upcase
    @account = RawWb::SellerAccount.create!(name: "WB cluster #{@token}", api_token: "token-#{@token}", company_type: "small")
    @store = Ec::Store.create!(platform: "wb", store_name: "WB cluster #{@token}", company_type: "small", wb_raw_account_id: @account.id)
    @region = RawWb::WarehouseRegion.create!(
      account: @account,
      warehouse_id: 900_000_000 + @token.to_i(16),
      warehouse_name: "Коледино #{@token}",
      region_name: "Центральный",
      source: "test",
      raw_json: {},
      synced_at: Time.zone.parse("2026-08-01 08:00:00")
    )
    @stats_order = RawWb::StatsOrder.create!(
      account: @account,
      order_date: Time.zone.parse("2026-08-20 10:00:00"),
      nm_id: 123456,
      srid: "WB-CLUSTER-#{@token}",
      warehouse_name: @region.warehouse_name,
      warehouse_type: "Склад WB",
      oblast_okrug_name: "Южный федеральный округ",
      region_name: "Краснодарский край",
      country_name: "Россия"
    )
    @order = Ec::Order.create!(platform: "wb", store: @store, order_key: "wb-cluster-#{@token}", order_status: "processing")
    @fulfillment = Ec::OrderFulfillment.create!(
      platform: "wb",
      store: @store,
      order: @order,
      external_fulfillment_id: @stats_order.srid,
      fulfillment_key: "wb-cluster-#{@token}",
      fulfillment_type: "fbw",
      status: "processing"
    )
    @link = Ec::OrderSourceLink.create!(
      platform: "wb",
      order: @order,
      fulfillment: @fulfillment,
      source_type: "RawWb::StatsOrder",
      source_id: @stats_order.id,
      source_role: "primary",
      source_key: @stats_order.srid
    )
  end

  teardown do
    @link&.destroy
    @fulfillment&.destroy
    @order&.destroy
    @stats_order&.destroy
    @region&.destroy
    @store&.destroy
    @account&.destroy
  end

  test "backfills WB fulfillment origin and destination clusters" do
    load SCRIPT_PATH

    assert_equal "Центральный", @fulfillment.reload.cluster_from
    assert_equal "Южный и Северо-Кавказский", @fulfillment.cluster_to
  end
end
