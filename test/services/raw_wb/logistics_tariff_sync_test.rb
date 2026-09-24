require "test_helper"
require "securerandom"

class RawWb::LogisticsTariffSyncTest < ActiveSupport::TestCase
  class FakeWbClient
    attr_reader :calls

    def initialize(response: nil, error: nil)
      @response = response
      @error = error
      @calls = []
    end

    def get(service, path, params = {})
      @calls << { service: service, path: path, params: params }
      raise @error if @error
      @response
    end
  end

  def create_account(suffix)
    RawWb::SellerAccount.create!(
      name: "wb-logistics-sync-#{suffix}-#{SecureRandom.hex(4)}",
      api_token: "token-#{SecureRandom.hex(6)}",
      company_type: "small",
      is_active: true
    )
  end

  def payload
    {
      "response" => {
        "data" => {
          "dtNextBox" => "2026-10-01",
          "dtTillMax" => "2026-12-31",
          "warehouseList" => [
            {
              "warehouseName" => "Коледино",
              "geoName" => "Центральный",
              "boxDeliveryBase" => "60",
              "boxDeliveryCoefExpr" => "155",
              "boxDeliveryLiter" => "11,2",
              "boxDeliveryMarketplaceBase" => "40",
              "boxDeliveryMarketplaceCoefExpr" => "125",
              "boxDeliveryMarketplaceLiter" => "9"
            },
            {
              "warehouseName" => "Казань",
              "geoName" => "Приволжский",
              "boxDeliveryBase" => "50",
              "boxDeliveryCoefExpr" => "145",
              "boxDeliveryLiter" => "10",
              "boxDeliveryMarketplaceBase" => "35",
              "boxDeliveryMarketplaceCoefExpr" => "120",
              "boxDeliveryMarketplaceLiter" => "8"
            }
          ]
        }
      }
    }
  end

  test "stores both FBO and FBS rows and promotes one monthly snapshot" do
    account = create_account("success")
    client = FakeWbClient.new(response: payload)

    begin
      result = RawWb::LogisticsTariffSync.new(
        date: Date.new(2026, 9, 23),
        account_scope: RawWb::SellerAccount.where(id: account.id),
        client_factory: ->(_) { client }
      ).run

      snapshot = RawWb::LogisticsTariffSnapshot.find(result[:snapshot_id])
      assert snapshot.succeeded?
      assert snapshot.is_current
      assert_equal Date.new(2026, 9, 23), snapshot.effective_from
      assert_equal Date.new(2026, 10, 1), snapshot.effective_to
      assert_equal 4, snapshot.item_count
      assert_equal 4, snapshot.logistics_tariffs.count
      assert_equal BigDecimal("1.55"), snapshot.logistics_tariffs.find_by!(delivery_mode: "fbo").logistics_coeff
      assert_equal BigDecimal("1.2"), snapshot.logistics_tariffs.find_by!(delivery_mode: "fbs", warehouse_name: "Казань").logistics_coeff
      assert_equal({ date: "2026-09-23" }, client.calls.first[:params])
    ensure
      cleanup_snapshots(account)
      RawWb::SellerAccount.where(id: account&.id).delete_all if account
    end
  end

  test "keeps the previous current snapshot when a refresh is invalid" do
    account = create_account("invalid")
    good = FakeWbClient.new(response: payload)

    begin
      first = RawWb::LogisticsTariffSync.new(
        date: Date.new(2026, 9, 23), account_scope: RawWb::SellerAccount.where(id: account.id),
        client_factory: ->(_) { good }
      ).run
      previous = RawWb::LogisticsTariffSnapshot.find(first[:snapshot_id])

      assert_raises(RawWb::LogisticsTariffSync::InvalidResponseError) do
        RawWb::LogisticsTariffSync.new(
          date: Date.new(2026, 10, 2), account_scope: RawWb::SellerAccount.where(id: account.id),
          client_factory: ->(_) { FakeWbClient.new(response: { "response" => { "data" => { "warehouseList" => [] } } }) }
        ).run
      end

      assert previous.reload.is_current
      assert_equal 1, RawWb::LogisticsTariffSnapshot.where(source_account_id: account.id, status: "failed").count
    ensure
      cleanup_snapshots(account)
      RawWb::SellerAccount.where(id: account&.id).delete_all if account
    end
  end

  private

  def cleanup_snapshots(account)
    return unless account

    ids = RawWb::LogisticsTariffSnapshot.where(source_account_id: account.id).select(:id)
    RawWb::LogisticsTariff.where(snapshot_id: ids).delete_all
    RawWb::LogisticsTariffSnapshot.where(source_account_id: account.id).delete_all
  end
end
