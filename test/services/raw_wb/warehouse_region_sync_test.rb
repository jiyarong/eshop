require "test_helper"

class RawWbWarehouseRegionSyncTest < ActiveSupport::TestCase
  class FakeWbClient
    attr_reader :posts

    def initialize
      @posts = []
    end

    def post(service, path, body = {})
      @posts << { service: service, path: path, body: body }

      case path
      when "/api/analytics/v1/stocks-report/wb-warehouses"
        {
          "data" => {
            "items" => [
              {
                "warehouseId" => 301981,
                "warehouseName" => "Владимир WB",
                "regionName" => "Центральный",
                "quantity" => 124
              },
              {
                "warehouseId" => 300571,
                "warehouseName" => "Екатеринбург - Перспективная 14",
                "regionName" => "Уральский",
                "quantity" => 70
              }
            ]
          }
        }
      when "/api/v2/stocks-report/offices"
        {
          "data" => {
            "regions" => [
              {
                "regionName" => "Приволжский",
                "offices" => [
                  {
                    "officeID" => 301805,
                    "officeName" => "Новосемейкино",
                    "metrics" => { "stockCount" => 1 }
                  }
                ]
              },
              {
                "regionName" => "Центральный",
                "offices" => [
                  {
                    "officeID" => 301981,
                    "officeName" => "Владимир WB",
                    "metrics" => { "stockCount" => 124 }
                  }
                ]
              }
            ]
          }
        }
      else
        raise "unexpected WB POST #{service} #{path}"
      end
    end
  end

  setup do
    @token = SecureRandom.hex(4).upcase
    @account = RawWb::SellerAccount.create!(
      name: "wb-region-sync-#{@token}",
      api_token: "wb-region-token-#{@token}",
      company_type: "small",
      is_active: true
    )
  end

  teardown do
    RawWb::WarehouseRegion.where(account_id: @account&.id).delete_all
    RawWb::SellerAccount.where(id: @account&.id).delete_all
  end

  test "syncs warehouse to region mappings from WB analytics reports" do
    now = Time.zone.parse("2026-07-20 05:30:00")
    fake_client = FakeWbClient.new

    result = RawWb::WarehouseRegionSync.run(
      account_scope: RawWb::SellerAccount.where(id: @account.id),
      client_factory: ->(_) { fake_client },
      now: now
    )

    assert_equal 3, result.dig(@account.id, :ok)
    assert fake_client.posts.any? { |call| call[:path] == "/api/analytics/v1/stocks-report/wb-warehouses" }
    assert fake_client.posts.any? { |call| call[:path] == "/api/v2/stocks-report/offices" }

    warehouse = RawWb::WarehouseRegion.find_by!(account_id: @account.id, warehouse_id: 301981)
    assert_equal "Владимир WB", warehouse.warehouse_name
    assert_equal "ВЛАДИМИР_WB", warehouse.normalized_warehouse_name
    assert_equal "Центральный", warehouse.region_name
    assert_equal "stocks_report_wb_warehouses", warehouse.source
    assert_equal now, warehouse.synced_at

    office = RawWb::WarehouseRegion.find_by!(account_id: @account.id, warehouse_id: 301805)
    assert_equal "Новосемейкино", office.warehouse_name
    assert_equal "Приволжский", office.region_name
    assert_equal "stocks_report_offices", office.source
  end
end
