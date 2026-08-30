require "test_helper"

class ErpAI::V2::MarketingInventoryContextTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(4).upcase
    @time_zone = ActiveSupport::TimeZone["Asia/Shanghai"]
    @sku = Ec::Sku.create!(sku_code: "MARKETING-INVENTORY-#{@token}", product_name: "Marketing inventory")
    @account_id = @token.to_i(16) % 2_000_000_000
    @account_id = 1 unless @account_id.positive?
    @account = RawOzon::SellerAccount.create!(
      company_name: "Marketing inventory account #{@token}",
      client_id: "marketing-inventory-#{@token}",
      api_key: "key-#{@token}",
      company_type: :small,
      is_active: true
    )
    @account_id = @account.id
    @store = Ec::Store.create!(
      platform: "ozon", store_name: "Marketing inventory #{@token}", company_type: "small",
      ozon_raw_account_id: @account_id
    )
    @product = Ec::SkuProduct.create!(
      sku: @sku, store: @store, product_id: "PRODUCT-#{@token}", platform_sku_id: "SKU-#{@token}"
    )
    Ec::SkuBatch.create!(
      sku_code: @sku.sku_code, batch_code: "MARKETING-INVENTORY-BATCH-#{@token}",
      status: "received", batch_type: :normal, purchased_quantity: 18, received_quantity: 18,
      purchase_unit_price_cny: 1
    )
    Ec::SkuInventoryLevel.create!(
      sku_code: @sku.sku_code, platform: "ozon", account_id: @account_id, store: @store,
      store_name: @store.store_name, fulfillment_type: "fbo", quantity: 6,
      is_latest: true, synced_at: Time.utc(2026, 8, 9, 3), metadata: { "source" => "test" }
    )
    Ec::Snapshot.create!(
      sku: @sku, snapshot_type: ErpAI::V2::MarketingInventoryContext::INVENTORY_SNAPSHOT_TYPE, snapshot_date: Date.new(2026, 8, 3),
      content: {
        overview: {
          incoming_quantity: 2, book_stock: 18, platform_inbound_stock: 1, platform_stock: 6,
          available_stock: 11, daily_sales_velocity: "1.2", turnover_days: "5.0",
          turnover_days_with_procurement: "6.7", out_of_stock: false,
          platform_totals: {
            "ozon" => { platform_stock: 6, out_of_stock: false, quantity_by_fulfillment: { fbo: 6 } }
          }
        }
      }
    )
  end

  teardown do
    Ec::Snapshot.where(snapshot_type: ErpAI::V2::MarketingInventoryContext::INVENTORY_SNAPSHOT_TYPE, sku_id: @sku.id).delete_all if @sku
    Ec::SkuInventoryLevel.where(sku_code: @sku&.sku_code).delete_all
    Ec::SkuBatch.where(sku_code: @sku&.sku_code).delete_all
    Ec::SkuProduct.where(id: @product&.id).delete_all
    Ec::Store.where(id: @store&.id).delete_all
    RawOzon::SellerAccount.where(id: @account&.id).delete_all
    Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
  end

  test "returns compact current channel and weekly inventory data" do
    result = described_context.call

    assert_equal ErpAI::V2::MarketingInventoryContext::INVENTORY_METRICS + %i[data_status as_of data_through scope], result.fetch(:current).keys
    assert_equal "available", result.dig(:current, :data_status)
    assert_equal 18, result.dig(:current, :book_stock)
    assert_equal 6, result.dig(:current, :platform_stock)
    assert_equal "2026-08-10", result.dig(:current, :as_of)
    assert_equal Time.utc(2026, 8, 9, 3), result.dig(:current, :data_through)
    assert_equal "sku_all_sources", result.dig(:current, :scope)
    assert_equal(
      {
        data_status: "complete",
        scope: "eligible_attributed_channels",
        eligible_channel_count: 1,
        missing_eligible_channel_count: 0,
        excluded_channel_count: 0,
        unattributed_inventory_level_count: 0,
        unattributed_platform_stock: 0,
        unattributed_inbound_stock: 0
      },
      result.fetch(:channel_coverage)
    )

    channel = result.fetch(:by_channel).sole
    assert_equal({ platform: "ozon", platform_stock: 6, fbo_stock: 6, total_stock: 6, out_of_stock: false }, channel.slice(:platform, :platform_stock, :fbo_stock, :total_stock, :out_of_stock))
    assert_equal Time.utc(2026, 8, 9, 3), channel.fetch(:data_through)
    assert_not channel.key?(:metadata)

    weekly = result.fetch(:weekly_snapshots)
    assert_equal "available", weekly.first.fetch(:data_status)
    assert_equal [ :platform, :platform_stock, :out_of_stock ], weekly.first.fetch(:platforms).sole.keys
    assert_not weekly.first.fetch(:platforms).sole.key?(:quantity_by_fulfillment)
    assert_equal true, weekly.last.fetch(:is_partial)
    assert_equal "no_records", weekly.last.fetch(:data_status)
  end

  test "keeps unbound levels in global current totals but excludes them from channel attribution" do
    orphan_store = Ec::Store.create!(
      platform: "ozon", store_name: "Orphan inventory #{@token}", company_type: "small",
      ozon_raw_account_id: @account_id + 1
    )
    Ec::SkuInventoryLevel.create!(
      sku_code: @sku.sku_code, platform: "ozon", account_id: @account_id + 1, store: orphan_store,
      store_name: orphan_store.store_name, fulfillment_type: "fbo", quantity: 99,
      is_latest: true, synced_at: Time.utc(2026, 8, 9, 4), metadata: {}
    )
    Ec::SkuInventoryLevel.create!(
      sku_code: @sku.sku_code, platform: "ozon", account_id: @account_id + 1, store: orphan_store,
      store_name: orphan_store.store_name, fulfillment_type: "inbound", quantity: 7,
      is_latest: true, synced_at: Time.utc(2026, 8, 9, 4), metadata: {}
    )
    Ec::SkuInventoryLevel.create!(
      sku_code: @sku.sku_code, platform: "ozon", account_id: @account_id + 1, store: orphan_store,
      store_name: orphan_store.store_name, fulfillment_type: "fbs", quantity: 40,
      is_latest: true, synced_at: Time.utc(2026, 8, 9, 4), metadata: {}
    )

    result = described_context.call

    assert_equal "partial_sources", result.dig(:current, :data_status)
    assert_equal 105, result.dig(:current, :platform_stock)
    assert_equal 7, result.dig(:current, :platform_inbound_stock)
    assert_equal(-94, result.dig(:current, :available_stock))
    assert_equal [ @store.id ], result.fetch(:by_channel).pluck(:store_id)
    assert_equal "partial", result.dig(:channel_coverage, :data_status)
    assert_equal 3, result.dig(:channel_coverage, :unattributed_inventory_level_count)
    assert_equal 99, result.dig(:channel_coverage, :unattributed_platform_stock)
    assert_equal 7, result.dig(:channel_coverage, :unattributed_inbound_stock)
  ensure
    Ec::SkuInventoryLevel.where(store_id: orphan_store&.id).delete_all
    Ec::Store.where(id: orphan_store&.id).delete_all
  end

  test "excludes inventory for an inactive store or account" do
    @store.update!(is_active: false)

    result = described_context.call

    assert_equal "partial_sources", result.dig(:current, :data_status)
    assert_equal 6, result.dig(:current, :platform_stock)
    assert_empty result.fetch(:by_channel)
    assert_equal "partial", result.dig(:channel_coverage, :data_status)
    assert_equal 1, result.dig(:channel_coverage, :excluded_channel_count)
    assert_equal 1, result.dig(:channel_coverage, :unattributed_inventory_level_count)
    assert_equal 6, result.dig(:channel_coverage, :unattributed_platform_stock)
  end

  test "excludes inventory for an inactive raw account" do
    @account.update!(is_active: false)

    result = described_context.call

    assert_equal "partial_sources", result.dig(:current, :data_status)
    assert_equal 6, result.dig(:current, :platform_stock)
    assert_empty result.fetch(:by_channel)
    assert_equal "partial", result.dig(:channel_coverage, :data_status)
    assert_equal 1, result.dig(:channel_coverage, :excluded_channel_count)
  end

  test "excludes inventory when one raw account maps to multiple ERP stores" do
    duplicate_store = Ec::Store.create!(
      platform: "ozon", store_name: "Duplicate inventory #{@token}", company_type: "small",
      ozon_raw_account_id: @account_id
    )
    duplicate_product = Ec::SkuProduct.create!(
      sku: @sku, store: duplicate_store, product_id: "DUPLICATE-PRODUCT-#{@token}", platform_sku_id: "DUPLICATE-SKU-#{@token}"
    )
    result = described_context.call

    assert_equal "partial_sources", result.dig(:current, :data_status)
    assert_equal 6, result.dig(:current, :platform_stock)
    assert_empty result.fetch(:by_channel)
    assert_equal "partial", result.dig(:channel_coverage, :data_status)
    assert_equal 2, result.dig(:channel_coverage, :excluded_channel_count)
    assert_equal 1, result.dig(:channel_coverage, :unattributed_inventory_level_count)
    assert_equal 6, result.dig(:channel_coverage, :unattributed_platform_stock)
  ensure
    Ec::SkuProduct.where(id: duplicate_product&.id).delete_all
    Ec::Store.where(id: duplicate_store&.id).delete_all
  end

  test "does not treat an absent inventory snapshot as zero stock" do
    Ec::SkuInventoryLevel.where(sku_code: @sku.sku_code).delete_all

    result = described_context.call

    assert_equal "no_records", result.dig(:current, :data_status)
    assert_nil result.dig(:current, :platform_stock)
    assert_nil result.dig(:current, :platform_inbound_stock)
    assert_nil result.dig(:current, :available_stock)
    assert_nil result.dig(:current, :out_of_stock)
    assert_equal "no_records", result.dig(:channel_coverage, :data_status)
    assert_equal 1, result.dig(:channel_coverage, :missing_eligible_channel_count)
  end

  test "separates inventory attribution coverage from a bound channel without snapshots" do
    second_account = RawOzon::SellerAccount.create!(
      company_name: "Marketing inventory second account #{@token}",
      client_id: "marketing-inventory-second-#{@token}", api_key: "second-key-#{@token}",
      company_type: :small, is_active: true
    )
    second_store = Ec::Store.create!(
      platform: "ozon", store_name: "Marketing inventory second #{@token}", company_type: "small",
      ozon_raw_account_id: second_account.id
    )
    second_product = Ec::SkuProduct.create!(
      sku: @sku, store: second_store, product_id: "SECOND-PRODUCT-#{@token}",
      platform_sku_id: "SECOND-SKU-#{@token}"
    )

    result = described_context.call

    assert_equal "partial_sources", result.dig(:current, :data_status)
    assert_equal "complete", result.dig(:channel_coverage, :data_status)
    assert_equal 2, result.dig(:channel_coverage, :eligible_channel_count)
    assert_equal 1, result.dig(:channel_coverage, :missing_eligible_channel_count)
    assert_equal 0, result.dig(:channel_coverage, :unattributed_inventory_level_count)
  ensure
    Ec::SkuProduct.where(id: second_product&.id).delete_all
    Ec::Store.where(id: second_store&.id).delete_all
    RawOzon::SellerAccount.where(id: second_account&.id).delete_all
  end

  private

  def described_context
    ErpAI::V2::MarketingInventoryContext.new(
      sku: @sku, period_from: Date.new(2026, 8, 3), period_to: Date.new(2026, 8, 10),
      today: Date.new(2026, 8, 10), time_zone: @time_zone
    )
  end
end
