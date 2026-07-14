require "test_helper"

class BackfillOzonFulfillmentClustersTest < ActiveSupport::TestCase
  SCRIPT_PATH = Rails.root.join("script/backfill_ozon_fulfillment_clusters.rb")

  setup do
    @token = SecureRandom.hex(4).upcase
    @account = RawOzon::SellerAccount.create!(
      client_id: "cluster-backfill-#{@token}",
      api_key: "test-api-key",
      company_name: "Cluster Backfill #{@token}",
      company_type: "general",
      raw_json: {}
    )
    @store = Ec::Store.create!(
      platform: "ozon",
      store_name: "Cluster Backfill #{@token}",
      company_type: "general",
      ozon_raw_account_id: @account.id
    )
    @order = Ec::Order.create!(
      platform: "ozon",
      store: @store,
      order_key: "cluster-backfill-order-#{@token}",
      order_status: "processing",
      ordered_at: Time.zone.parse("2026-07-01 10:00:00")
    )
    @fbo = RawOzon::PostingFbo.create!(
      account: @account,
      posting_number: "CLUSTER-FBO-#{@token}",
      status: "delivered",
      financial_data: {
        "cluster_from" => "Москва, МО и Дальние регионы",
        "cluster_to" => "Казань"
      },
      raw_json: {},
      created_at: Time.zone.parse("2026-07-01 10:00:00"),
      synced_at: Time.zone.parse("2026-07-01 10:05:00")
    )
    @fbs = RawOzon::PostingFbs.create!(
      account: @account,
      posting_number: "CLUSTER-FBS-#{@token}",
      status: "delivering",
      financial_data: {
        "cluster_from" => "Беларусь",
        "cluster_to" => "Санкт-Петербург и СЗО"
      },
      raw_json: {},
      created_at: Time.zone.parse("2026-07-02 10:00:00"),
      synced_at: Time.zone.parse("2026-07-02 10:05:00")
    )
    @fbo_fulfillment = fulfillment_for(@fbo, "RawOzon::PostingFbo", "fbo")
    @fbs_fulfillment = fulfillment_for(@fbs, "RawOzon::PostingFbs", "fbs")
  end

  teardown do
    Ec::OrderFulfillment.where(id: [@fbo_fulfillment&.id, @fbs_fulfillment&.id].compact).delete_all
    Ec::Order.where(id: @order&.id).delete_all
    RawOzon::PostingFbo.where(id: @fbo&.id).delete_all
    RawOzon::PostingFbs.where(id: @fbs&.id).delete_all
    @store&.destroy
    @account&.destroy
  end

  test "backfills ozon fulfillment clusters from raw posting financial data" do
    load SCRIPT_PATH

    assert_equal "Москва, МО и Дальние регионы", @fbo_fulfillment.reload.cluster_from
    assert_equal "Казань", @fbo_fulfillment.cluster_to
    assert_equal "Беларусь", @fbs_fulfillment.reload.cluster_from
    assert_equal "Санкт-Петербург и СЗО", @fbs_fulfillment.cluster_to
  end

  private

  def fulfillment_for(posting, source_type, fulfillment_type)
    Ec::OrderFulfillment.create!(
      platform: "ozon",
      store: @store,
      order: @order,
      external_fulfillment_id: posting.posting_number,
      fulfillment_key: "cluster-backfill-#{posting.posting_number}",
      fulfillment_type: fulfillment_type,
      status: "processing",
      raw_source_type: source_type,
      raw_source_id: posting.id
    )
  end
end
