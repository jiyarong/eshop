require "test_helper"

class RawWbWarehouseNameResolverTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(5).upcase
    @account = RawWb::SellerAccount.create!(
      name: "wb-resolver-#{@token}",
      api_token: "token-#{@token}",
      company_type: "small",
      is_active: true
    )
    @region = RawWb::WarehouseRegion.create!(
      account: @account,
      warehouse_id: 800_000_000 + rand(10_000),
      warehouse_name: "Тестовый склад WB #{@token}",
      normalized_warehouse_name: "unused",
      region_name: "Центральный",
      source: "test",
      raw_json: {},
      synced_at: Time.current,
      last_seen_at: Time.current
    )
  end

  teardown do
    RawWb::WarehouseNameMapping.where(account_id: @account&.id).delete_all
    RawWb::WarehouseNameMapping.where(mapping_source: "test", evidence: { token: @token }).delete_all
    RawWb::WarehouseRegion.where(account_id: @account&.id).delete_all
    RawWb::SellerAccount.where(id: @account&.id).delete_all
  end

  test "resolves current names and verified account aliases" do
    direct = RawWb::WarehouseNameResolver.resolve(
      account_id: @account.id,
      warehouse_name: @region.warehouse_name,
      on: Date.new(2026, 7, 1)
    )
    assert_equal @region.warehouse_id, direct.warehouse_id
    assert_equal :current_name, direct.match_type

    mapping = RawWb::WarehouseNameMapping.create!(
      account: @account,
      historical_name: "Старое имя #{@token}",
      warehouse_id: @region.warehouse_id,
      canonical_name: @region.warehouse_name,
      region_name: @region.region_name,
      mapping_source: "manual",
      confidence: 1,
      status: "verified",
      valid_from: Date.new(2026, 1, 1)
    )
    resolved = RawWb::WarehouseNameResolver.resolve(
      account_id: @account.id,
      warehouse_name: mapping.historical_name,
      on: Date.new(2026, 7, 1)
    )
    assert_equal @region.warehouse_id, resolved.warehouse_id
    assert_equal :account_alias, resolved.match_type
  end

  test "does not use candidates or mappings outside their effective dates" do
    mapping = RawWb::WarehouseNameMapping.create!(
      account: @account,
      historical_name: "Кандидат #{@token}",
      warehouse_id: @region.warehouse_id,
      canonical_name: @region.warehouse_name,
      region_name: @region.region_name,
      mapping_source: "manual",
      confidence: 0.8,
      status: "candidate",
      valid_from: Date.new(2027, 1, 1)
    )

    assert_nil RawWb::WarehouseNameResolver.resolve(
      account_id: @account.id,
      warehouse_name: mapping.historical_name,
      on: Date.new(2026, 7, 1)
    )
  end

  test "resolves the seeded Samara historical warehouse name" do
    RawWb::WarehouseNameMapping.create!(
      historical_name: "Самара (Новосемейкино)",
      warehouse_id: 301_805,
      canonical_name: "Новосемейкино",
      region_name: "Приволжский",
      mapping_source: "test",
      confidence: 1,
      status: "verified",
      evidence: { token: @token }
    )

    resolved = RawWb::WarehouseNameResolver.resolve(
      account_id: @account.id,
      warehouse_name: "Самара (Новосемейкино)",
      on: Date.new(2026, 7, 1)
    )

    assert_equal 301_805, resolved.warehouse_id
    assert_equal "Новосемейкино", resolved.warehouse_name
    assert_equal "Приволжский", resolved.region_name
    assert_equal :global_alias, resolved.match_type
  end
end
