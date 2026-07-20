require "test_helper"

class RawOzonWarehouseClusterSyncTest < ActiveSupport::TestCase
  class FakeOzonClient
    def post(path, _body = {})
      raise "unexpected Ozon POST #{path}" unless path == "/v2/cluster/list"

      {
        "result" => [
          {
            "macrolocal_cluster_id" => 4039,
            "data" => {
              "macrolocal_cluster" => {
                "name" => "Москва, МО и Дальние регионы",
                "country" => { "name" => "Россия" }
              },
              "fulfillments" => [
                { "warehouse_id" => 1020001853757000, "name" => "ДОМОДЕДОВО_РФЦ" },
                { "warehouse_id" => 1020000435290000, "name" => "ГРИВНО_РФЦ" }
              ]
            }
          }
        ]
      }
    end
  end

  setup do
    @token = SecureRandom.hex(4).upcase
    @account = RawOzon::SellerAccount.create!(
      company_name: "cluster-sync-#{@token}",
      client_id: "cluster-client-#{@token}",
      api_key: "cluster-key-#{@token}",
      company_type: "small",
      is_active: true
    )
  end

  teardown do
    RawOzon::WarehouseCluster.where(account_id: @account&.id).delete_all
    RawOzon::SellerAccount.where(id: @account&.id).delete_all
  end

  test "syncs warehouse to cluster mappings from Ozon cluster list" do
    now = Time.zone.parse("2026-07-20 06:00:00")

    result = RawOzon::WarehouseClusterSync.run(
      account_scope: RawOzon::SellerAccount.where(id: @account.id),
      client_factory: ->(_) { FakeOzonClient.new },
      now: now
    )

    assert_equal 2, result.dig(@account.id, :ok)
    warehouse = RawOzon::WarehouseCluster.find_by!(account_id: @account.id, warehouse_name: "ДОМОДЕДОВО_РФЦ")
    assert_equal 1020001853757000, warehouse.warehouse_id
    assert_equal "ДОМОДЕДОВО_РФЦ", warehouse.normalized_warehouse_name
    assert_equal 4039, warehouse.macrolocal_cluster_id
    assert_equal "Москва, МО и Дальние регионы", warehouse.cluster_name
    assert_equal "Россия", warehouse.country_name
    assert_equal now, warehouse.synced_at
  end
end
