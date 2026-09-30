require "test_helper"

class Ec::PlatformFbsStockUpdaterTest < ActiveSupport::TestCase
  FakeAccount = Struct.new(:id, :api_token, :client_id, :api_key)

  class FakeWbClient
    attr_reader :calls

    def initialize
      @calls = []
    end

    def get(service, path)
      @calls << [ :get, service, path ]
      [ { "id" => 123, "deliveryType" => 1 } ]
    end

    def put(service, path, body)
      @calls << [ :put, service, path, body ]
      { "ok" => true }
    end
  end

  class FakeOzonClient
    attr_reader :calls

    def initialize
      @calls = []
    end

    def post(path, body)
      @calls << [ :post, path, body ]
      return { "products" => [ { "warehouse_id" => 456 } ] } if path.include?("stocks-by-warehouse")
      { "result" => [ { "updated" => true } ] }
    end
  end

  setup do
    @wb_account = FakeAccount.new(1, "token", nil, nil)
    @ozon_account = FakeAccount.new(2, nil, "client", "key")
  end

  test "dry run validates and does not build API clients" do
    output = StringIO.new
    client_built = false
    updater = build_updater(apply: false, stdout: output,
      wb_factory: ->(_account) { client_built = true },
      ozon_factory: ->(_account) { client_built = true })

    result = with_accounts { updater.call }

    assert_equal({ dry_run: true, updates: 2 }, result)
    assert_not client_built
    assert_includes output.string, "DRY RUN"
    assert_includes output.string, "No platform API was called"
  end

  test "apply sends WB put and Ozon post with warehouse-specific stock" do
    wb_client = FakeWbClient.new
    ozon_client = FakeOzonClient.new
    updater = build_updater(apply: true,
      wb_factory: ->(_account) { wb_client },
      ozon_factory: ->(_account) { ozon_client })

    result = with_accounts { updater.call }

    assert_equal false, result[:dry_run]
    assert_includes wb_client.calls, [
      :put, :marketplace, "/api/v3/stocks/123",
      { stocks: [ { sku: "WB-BARCODE", amount: 7 } ] }
    ]
    assert_includes ozon_client.calls, [
      :post, "/v2/products/stocks",
      { stocks: [ { offer_id: "OZ-OFFER", stock: 9, warehouse_id: 456 } ] }
    ]
  end

  test "rejects duplicate targets before building clients" do
    updates = [ wb_update, wb_update ]
    updater = Ec::PlatformFbsStockUpdater.new(
      updates: updates,
      wb_account_finder: ->(_id) { @wb_account }
    )

    error = assert_raises(Ec::PlatformFbsStockUpdater::PlanError) do
      updater.call
    end

    assert_includes error.message, "duplicate targets"
  end

  test "rejects an Ozon warehouse that is not returned for the product" do
    ozon_client = FakeOzonClient.new
    updater = Ec::PlatformFbsStockUpdater.new(
      updates: [ ozon_update.merge(warehouse_id: 999) ],
      apply: true,
      ozon_client_factory: ->(_account) { ozon_client },
      ozon_account_finder: ->(_id) { @ozon_account }
    )

    error = assert_raises(Ec::PlatformFbsStockUpdater::PlanError) do
      updater.call
    end

    assert_includes error.message, "not returned for the requested products"
    assert_equal 1, ozon_client.calls.size
  end

  test "preflights every platform before sending any stock update" do
    wb_client = FakeWbClient.new
    ozon_client = FakeOzonClient.new
    updater = Ec::PlatformFbsStockUpdater.new(
      updates: [ wb_update, ozon_update.merge(warehouse_id: 999) ],
      apply: true,
      wb_client_factory: ->(_account) { wb_client },
      ozon_client_factory: ->(_account) { ozon_client },
      wb_account_finder: ->(_id) { @wb_account },
      ozon_account_finder: ->(_id) { @ozon_account }
    )

    assert_raises(Ec::PlatformFbsStockUpdater::PlanError) { updater.call }

    assert_equal [ [ :get, :marketplace, "/api/v3/warehouses" ] ], wb_client.calls
    assert_equal 1, ozon_client.calls.size
  end

  private

  def build_updater(apply:, stdout: StringIO.new, wb_factory: nil, ozon_factory: nil)
    Ec::PlatformFbsStockUpdater.new(
      updates: [ wb_update, ozon_update ],
      apply: apply,
      stdout: stdout,
      wb_client_factory: wb_factory,
      ozon_client_factory: ozon_factory,
      wb_account_finder: ->(_id) { @wb_account },
      ozon_account_finder: ->(_id) { @ozon_account }
    )
  end

  def wb_update
    { platform: "wb", account_id: 1, warehouse_id: 123, barcode: "WB-BARCODE", sku_code: "SKU-1", stock: 7 }
  end

  def ozon_update
    { platform: "ozon", account_id: 2, warehouse_id: 456, offer_id: "OZ-OFFER", sku_code: "SKU-1", stock: 9 }
  end

  def with_accounts
    yield
  end
end
