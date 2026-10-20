require "test_helper"

class RawOzon::SupplyClientTest < ActiveSupport::TestCase
  test "uses current schemas and disables automatic retries for platform writes" do
    calls = []
    transport = Object.new
    transport.define_singleton_method(:post) do |path, body, **options|
      calls << [path, body, options]
      {}
    end
    client = RawOzon::SupplyClient.new(account: nil, client: transport)
    client.create_draft(type: "CROSSDOCK", cluster_id: 761, items: [{ sku: 1001, quantity: 20 }],
      drop_off: { warehouse_id: 9001, warehouse_type: "SORTING_CENTER" })
    client.create_supply(draft_id: 123, supply_type: "CROSSDOCK")
    client.supply_status("123")
    client.create_cargoes(supply_id: "456", cargoes: [])
    client.cargoes_info("operation")

    assert_equal "/v1/draft/crossdock/create", calls[0][0]
    assert_equal({ macrolocal_cluster_id: 761, items: [{ sku: 1001, quantity: 20 }] }, calls[0][1][:cluster_info])
    assert_equal "FULL", calls[0][1][:deletion_sku_mode]
    assert_equal "DROPOFF", calls[0][1].dig(:delivery_info, :type)
    assert_equal({ retry_on_error: false }, calls[0][2])
    assert_equal({ retry_on_error: false }, calls[1][2])
    assert_equal ["/v2/draft/supply/create/status", { draft_id: 123 }, {}], calls[2]
    assert_equal false, calls[3][1][:delete_current_version]
    assert_equal({ retry_on_error: false }, calls[3][2])
    assert_equal "/v2/cargoes/create/info", calls[4][0]
  end

  test "reads every bundle page and rejects a nonadvancing cursor" do
    calls = []
    transport = Object.new
    transport.define_singleton_method(:post) do |path, body|
      calls << body
      body[:last_id].empty? ? { "items" => [{ "sku" => 1 }], "has_next" => true, "last_id" => "next" } : { "items" => [{ "sku" => 2 }] }
    end
    client = RawOzon::SupplyClient.new(account: nil, client: transport)
    assert_equal [1, 2], client.bundle_items("bundle").map { |row| row["sku"] }
    assert_equal ["", "next"], calls.map { |row| row[:last_id] }
  end
end
