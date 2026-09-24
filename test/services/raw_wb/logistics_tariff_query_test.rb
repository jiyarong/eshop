require "test_helper"

class RawWb::LogisticsTariffQueryTest < ActiveSupport::TestCase
  class FakeClient
    attr_reader :calls

    def initialize(response)
      @response = response
      @calls = []
    end

    def get(service, path, params = {})
      @calls << { service: service, path: path, params: params }
      @response
    end
  end

  setup do
    @account = RawWb::SellerAccount.create!(
      name: "wb-logistics-query-#{SecureRandom.hex(4)}",
      api_token: "token-#{SecureRandom.hex(4)}",
      company_type: "small",
      is_active: true
    )
  end

  teardown do
    @account&.destroy!
  end

  test "maps the official FBO fields and converts coefficient percentages" do
    client = FakeClient.new(
      "response" => {
        "data" => {
          "dtNextBox" => "2026-09-01",
          "dtTillMax" => "2026-09-30",
          "warehouseList" => [
            { "warehouseName" => "Коледино", "geoName" => "Центральный", "boxDeliveryBase" => "60", "boxDeliveryCoefExpr" => "155", "boxDeliveryLiter" => "11,2", "boxDeliveryMarketplaceBase" => "40", "boxDeliveryMarketplaceCoefExpr" => "125", "boxDeliveryMarketplaceLiter" => "9" },
            { "warehouseName" => "Казань", "geoName" => "Приволжский", "boxDeliveryBase" => "50", "boxDeliveryCoefExpr" => "145", "boxDeliveryLiter" => "10", "boxDeliveryMarketplaceBase" => "35", "boxDeliveryMarketplaceCoefExpr" => "120", "boxDeliveryMarketplaceLiter" => "8" }
          ]
        }
      }
    )

    result = RawWb::LogisticsTariffQuery.run(
      date: Date.new(2026, 9, 23), delivery_mode: "fbo",
      account_scope: RawWb::SellerAccount.where(id: @account.id), client_factory: ->(_) { client }
    )

    assert_equal "/api/v1/tariffs/box", client.calls.first[:path]
    assert_equal({ date: "2026-09-23" }, client.calls.first[:params])
    assert_equal BigDecimal("1.55"), result[:rows].first[:logistics_coeff]
    assert_equal BigDecimal("11.2"), result[:rows].first[:liter_rub]
    assert_equal BigDecimal("1.5"), result[:average_logistics_coeff]
    assert_equal BigDecimal("10.6"), result[:average_liter_rub]
  end

  test "uses the marketplace fields for FBS and supports warehouse filtering" do
    client = FakeClient.new(
      "response" => {
        "data" => {
          "warehouseList" => [
            { "warehouseName" => "Коледино", "geoName" => "Центральный", "boxDeliveryBase" => "60", "boxDeliveryCoefExpr" => "155", "boxDeliveryLiter" => "11,2", "boxDeliveryMarketplaceBase" => "40", "boxDeliveryMarketplaceCoefExpr" => "125", "boxDeliveryMarketplaceLiter" => "9" },
            { "warehouseName" => "Казань", "geoName" => "Приволжский", "boxDeliveryBase" => "50", "boxDeliveryCoefExpr" => "145", "boxDeliveryLiter" => "10", "boxDeliveryMarketplaceBase" => "35", "boxDeliveryMarketplaceCoefExpr" => "120", "boxDeliveryMarketplaceLiter" => "8" }
          ]
        }
      }
    )

    result = RawWb::LogisticsTariffQuery.run(
      delivery_mode: "fbs", warehouse: "казань",
      account_scope: RawWb::SellerAccount.where(id: @account.id), client_factory: ->(_) { client }
    )

    assert_equal 1, result[:matched_count]
    assert_equal BigDecimal("35"), result[:rows].first[:base_rub]
    assert_equal BigDecimal("1.2"), result[:rows].first[:logistics_coeff]
    assert_equal BigDecimal("8"), result[:rows].first[:liter_rub]
  end

  test "reads the effective database snapshot without calling the WB API" do
    snapshot = RawWb::LogisticsTariffSnapshot.create!(
      status: "succeeded",
      source_account: @account,
      requested_date: Date.new(2026, 9, 1),
      effective_from: Date.new(2026, 9, 1),
      effective_to: Date.new(2026, 10, 1),
      fetched_at: Time.current,
      is_current: true
    )
    RawWb::LogisticsTariff.create!(
      snapshot: snapshot,
      delivery_mode: "fbo",
      warehouse_name: "Коледино",
      geo_name: "Центральный",
      base_rub: 60,
      logistics_coeff: 1.55,
      coefficient_percent: 155,
      liter_rub: 11.2
    )

    result = RawWb::LogisticsTariffQuery.run(date: Date.new(2026, 9, 15), delivery_mode: "fbo")

    assert_equal snapshot.id, result[:snapshot_id]
    assert_equal 1, result[:matched_count]
    assert_equal BigDecimal("1.55"), result[:average_logistics_coeff]
    assert_equal "Коледино", result[:rows].first[:warehouse_name]
  ensure
    snapshot&.destroy!
  end

  test "raises a clear error when no effective snapshot exists" do
    assert_raises(RawWb::LogisticsTariffQuery::NoSnapshotError) do
      RawWb::LogisticsTariffQuery.run(date: Date.new(2000, 1, 1), delivery_mode: "fbo")
    end
  end
end
