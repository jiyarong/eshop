require "test_helper"

class ErpAI::V2::MarketingContextTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(4).upcase
    @sku = Ec::Sku.create!(sku_code: "MARKETING-COMPACT-#{@token}", product_name: "Marketing compact")
    @wb_account = RawWb::SellerAccount.create!(
      name: "Marketing WB #{@token}", api_token: "wb-#{@token}", company_type: :small, is_active: true
    )
    @ozon_account = RawOzon::SellerAccount.create!(
      company_name: "Marketing Ozon #{@token}", client_id: "ozon-#{@token}", api_key: "key-#{@token}",
      company_type: :small, is_active: true
    )
    @wb_store = Ec::Store.create!(
      platform: "wb", store_name: "Marketing WB #{@token}", company_type: "small",
      wb_raw_account_id: @wb_account.id
    )
    @ozon_store = Ec::Store.create!(
      platform: "ozon", store_name: "Marketing Ozon #{@token}", company_type: "small",
      ozon_raw_account_id: @ozon_account.id
    )
    @wb_product = Ec::SkuProduct.create!(sku_code: @sku.sku_code, store: @wb_store, product_id: "101")
    @ozon_product = Ec::SkuProduct.create!(
      sku_code: @sku.sku_code, store: @ozon_store, product_id: "OZ-101", platform_sku_id: "201"
    )
  end

  teardown do
    Ec::SkuProduct.where(id: [ @wb_product&.id, @ozon_product&.id ]).delete_all
    Ec::Store.where(id: [ @wb_store&.id, @ozon_store&.id ]).delete_all
    RawWb::SellerAccount.where(id: @wb_account&.id).delete_all
    RawOzon::SellerAccount.where(id: @ozon_account&.id).delete_all
    Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
  end

  test "compacts active store channels with normalized platform marketing metrics" do
    funnel_calls = []
    advertising_calls = []
    search_calls = []
    inventory_calls = []
    result = described_context(
      platform_products: [
        { store_id: @wb_store.id, platform: "wb", product_id: "101", product_info: { title: "WB title" } },
        { store_id: @ozon_store.id, platform: "ozon", product_id: "OZ-101", product_info: { name: "Ozon title" } }
      ],
      funnel: [
        week_with_stores(
          { store_ref: "wb:#{@wb_account.id}", data: [ { open_card: 100, add_to_cart: 20, orders: 5, orders_sum: 500, buyouts: 4, cancel_count: 1, add_to_wishlist: 7, conv_to_cart: 20, cart_to_order: 25, buyout_percent: 80 } ] },
          { store_ref: "ozon:#{@ozon_account.id}", data: [ { hits_view: 200, hits_view_search: 120, hits_view_pdp: 80, session_view: 70, hits_tocart_pdp: 16, ordered_units: 4, revenue: 600, delivered_units: 3, returns_count: 1, cancellations: 2, average_price: 150, position_category: 9, search_to_card_conversion: 66, conv_tocart: 20, cart_to_order: 25, order_conversion: 2 } ] }
        )
      ],
      advertising: [
        week_with_stores(
          { store_id: @wb_store.id, data_status: "available", days_with_data: 7, data_through: "2026-08-09", data: [ { data_status: "available", platform_sku_id: "101", currency: "MIXED", impressions: 1000, clicks: 50, spend: 90, attributed_revenue: 300, avg_cpc: 1.8, cpo: 18, drr_pct: 30, roas: 3 } ] },
          { store_id: @ozon_store.id, data_status: "available", days_with_data: 7, data_through: "2026-08-09", data: [ { data_status: "available", platform_sku_id: "201", currency: "RUB", impressions: 800, clicks: 40, spend: 70, attributed_revenue: 280, avg_cpc: 1.75, cpo: 17.5, drr_pct: 25, roas: 4 } ] }
        )
      ],
      search: [
        week_with_stores(
          { store_id: @wb_store.id, data: [ { term_count: 12, views: 90, avg_position: 8, add_to_cart: 18, orders: 6, cart_conversion: 20, conversion: 33, visibility: 44 } ] },
          { store_id: @ozon_store.id, data: [ { search_volume: 900, views: 100, avg_position: 6, conversion: 11 } ] }
        )
      ],
      funnel_calls:,
      advertising_calls:,
      search_calls:,
      inventory_calls:
    )

    assert_equal [
      { ref: "ozon:#{@ozon_account.id}", platform: "ozon", name: @ozon_store.store_name, label: @ozon_store.store_name },
      { ref: "wb:#{@wb_account.id}", platform: "wb", name: @wb_store.store_name, label: @wb_store.store_name }
    ], funnel_calls.sole.fetch(:store_options)
    expected_store_ids = [ @ozon_store.id, @wb_store.id ].sort
    assert_equal expected_store_ids, advertising_calls.sole.fetch(:store_ids).sort
    assert_equal expected_store_ids, search_calls.sole.fetch(:store_ids).sort
    assert_equal expected_store_ids, inventory_calls.sole.fetch(:channels).pluck(:store_id).sort

    listings = result.dig(:sku, :listings)
    assert_equal @wb_product.id, listings.find { |listing| listing[:platform] == "wb" }.fetch(:sku_product_id)
    assert_equal @ozon_product.id, listings.find { |listing| listing[:platform] == "ozon" }.fetch(:sku_product_id)

    week = result.dig(:channel_performance, :weekly).sole
    wb = week.fetch(:channels).find { |channel| channel[:platform] == "wb" }
    ozon = week.fetch(:channels).find { |channel| channel[:platform] == "ozon" }

    assert_equal 100, wb.dig(:funnel, :views)
    assert_equal 4, wb.dig(:funnel, :fulfilled_orders)
    assert_equal 80, wb.dig(:funnel, :fulfillment_pct)
    assert_not wb.fetch(:funnel).key?(:revenue)
    assert_equal 200, ozon.dig(:funnel, :impressions)
    assert_equal 120, ozon.dig(:funnel, :search_impressions)
    assert_equal 2, ozon.dig(:funnel, :cancellations)
    assert_equal 2, ozon.dig(:funnel, :impression_to_order_pct)
    assert_not ozon.fetch(:funnel).key?(:average_price)

    wb_ad = wb.dig(:advertising, :listings).sole
    assert_equal "unavailable_mixed_currency", wb_ad.fetch(:monetary_data_status)
    ErpAI::V2::MarketingContext::MIXED_CURRENCY_METRICS.each { |metric| assert_nil wb_ad.fetch(metric) }
    assert_equal 1_000, wb_ad.fetch(:impressions)
    assert_equal 70, ozon.dig(:advertising, :listings).sole.fetch(:spend)

    assert_equal 12, wb.dig(:search_visibility, :term_count)
    assert_nil wb.dig(:search_visibility, :search_volume)
    assert_equal 44, wb.dig(:search_visibility, :visibility_pct)
    assert_nil ozon.dig(:search_visibility, :term_count)
    assert_equal 900, ozon.dig(:search_visibility, :search_volume)
    assert_equal 11, ozon.dig(:search_visibility, :search_to_view_pct)
  end

  test "marks inactive and unlinked store sources unavailable" do
    @wb_store.update!(is_active: false)
    @ozon_store.update!(ozon_raw_account_id: nil)

    result = described_context(
      platform_products: [], funnel: [], advertising: [], search: []
    )

    channels = result.dig(:channel_performance, :weekly).sole.fetch(:channels)
    reasons = channels.index_by { |channel| channel.fetch(:platform) }.transform_values { |channel| channel.fetch(:source_reason) }
    assert_equal({ "wb" => "inactive_store", "ozon" => "store_account_not_linked" }, reasons)
    channels.each do |channel|
      expected = { data_status: "unavailable", reason: channel.fetch(:source_reason) }
      assert_equal expected, channel.fetch(:funnel)
      assert_equal expected, channel.fetch(:advertising)
      assert_equal expected, channel.fetch(:search_visibility)
    end
  end

  test "aggregates multiple funnel rows within a channel" do
    result = described_context(
      platform_products: [],
      funnel: [
        week_with_stores(
          {
            store_ref: "wb:#{@wb_account.id}",
            data: [
              { open_card: 100, add_to_cart: 20, orders: 5, buyouts: 4, cancel_count: 1, add_to_wishlist: 2 },
              { open_card: 50, add_to_cart: 10, orders: 2, buyouts: 1, cancel_count: 0, add_to_wishlist: 3 }
            ]
          }
        )
      ],
      advertising: [],
      search: []
    )

    wb_funnel = result.dig(:channel_performance, :weekly).sole.fetch(:channels)
      .find { |channel| channel.fetch(:platform) == "wb" }.fetch(:funnel)

    assert_equal 150, wb_funnel.fetch(:views)
    assert_equal 30, wb_funnel.fetch(:add_to_cart)
    assert_equal 7, wb_funnel.fetch(:orders)
    assert_equal 5, wb_funnel.fetch(:fulfilled_orders)
    assert_equal 20, wb_funnel.fetch(:view_to_cart_pct)
    assert_equal 23.33, wb_funnel.fetch(:cart_to_order_pct)
    assert_equal 71.43, wb_funnel.fetch(:fulfillment_pct)
  end

  test "weights Ozon search position by search impressions when aggregating products" do
    result = described_context(
      platform_products: [],
      funnel: [
        week_with_stores(
          {
            store_ref: "ozon:#{@ozon_account.id}",
            data: [
              {
                hits_view: 1_000, hits_view_search: 100, hits_view_pdp: 80, session_view: 70,
                hits_tocart_pdp: 16, ordered_units: 4, delivered_units: 3,
                returns_count: 0, cancellations: 0, position_category: 10
              },
              {
                hits_view: 100, hits_view_search: 10, hits_view_pdp: 8, session_view: 7,
                hits_tocart_pdp: 2, ordered_units: 1, delivered_units: 1,
                returns_count: 0, cancellations: 0, position_category: 20
              }
            ]
          }
        )
      ],
      advertising: [],
      search: []
    )

    ozon_funnel = result.dig(:channel_performance, :weekly).sole.fetch(:channels)
      .find { |channel| channel.fetch(:platform) == "ozon" }.fetch(:funnel)

    assert_equal 10.91, ozon_funnel.fetch(:average_search_position)
    assert_equal 1_100, ozon_funnel.fetch(:impressions)
    assert_equal 5, ozon_funnel.fetch(:orders)
  end

  test "does not turn missing funnel counts into zero during aggregation" do
    result = described_context(
      platform_products: [],
      funnel: [
        week_with_stores(
          {
            store_ref: "wb:#{@wb_account.id}",
            data: [
              { open_card: 100, add_to_cart: 10, orders: 2, buyouts: 1, cancel_count: 0, add_to_wishlist: 1 },
              { open_card: 50, add_to_cart: nil, orders: 1, buyouts: 1, cancel_count: 0, add_to_wishlist: 1 }
            ]
          }
        )
      ],
      advertising: [],
      search: []
    )

    wb_funnel = result.dig(:channel_performance, :weekly).sole.fetch(:channels)
      .find { |channel| channel.fetch(:platform) == "wb" }.fetch(:funnel)

    assert_equal 150, wb_funnel.fetch(:views)
    assert_nil wb_funnel.fetch(:add_to_cart)
    assert_nil wb_funnel.fetch(:cart_to_order_pct)
  end

  test "treats malformed numeric metrics as unavailable instead of raising" do
    result = described_context(
      platform_products: [],
      funnel: [
        week_with_stores(
          {
            store_ref: "wb:#{@wb_account.id}",
            data: [
              { open_card: 100, add_to_cart: [], orders: 2, buyouts: 1, cancel_count: 0, add_to_wishlist: 1 },
              { open_card: 50, add_to_cart: 10, orders: 1, buyouts: 1, cancel_count: 0, add_to_wishlist: 1 }
            ]
          }
        )
      ],
      advertising: [
        week_with_stores(
          {
            store_id: @wb_store.id,
            data_status: "available",
            data: [ { data_status: "available", platform_sku_id: "101", impressions: [], spend: [] } ]
          }
        )
      ],
      search: [
        week_with_stores(
          { store_id: @wb_store.id, data: [ { term_count: [], views: {}, avg_position: "not-a-number" } ] }
        )
      ]
    )

    wb = result.dig(:channel_performance, :weekly).sole.fetch(:channels)
      .find { |channel| channel.fetch(:platform) == "wb" }
    assert_nil wb.dig(:funnel, :add_to_cart)
    assert_nil wb.dig(:funnel, :cart_to_order_pct)
    assert_equal 1, wb.dig(:advertising, :listings).size
    assert_nil wb.dig(:advertising, :listings).sole.fetch(:impressions)
    assert_equal "available", wb.dig(:search_visibility, :data_status)
  end

  test "preserves a funnel source failure as channel-level unavailable data" do
    result = described_context(
      platform_products: [],
      funnel: [
        week_with_stores(
          {
            store_ref: "wb:#{@wb_account.id}",
            data_status: "unavailable",
            reason: "source_unavailable",
            data: []
          }
        )
      ],
      advertising: [],
      search: []
    )

    wb_channel = result.dig(:channel_performance, :weekly).sole.fetch(:channels)
      .find { |channel| channel.fetch(:platform) == "wb" }
    assert_equal(
      { data_status: "unavailable", reason: "source_unavailable" },
      wb_channel.fetch(:funnel)
    )
  end

  test "preserves advertising and search source failures at channel level" do
    result = described_context(
      platform_products: [],
      funnel: [],
      advertising: [
        week_with_stores(
          {
            store_id: @wb_store.id,
            data_status: "unavailable",
            reason: "source_unavailable",
            data: []
          }
        )
      ],
      search: [
        week_with_stores(
          {
            store_id: @wb_store.id,
            data_status: "unavailable",
            reason: "source_unavailable",
            data: []
          }
        )
      ]
    )

    wb_channel = result.dig(:channel_performance, :weekly).sole.fetch(:channels)
      .find { |channel| channel.fetch(:platform) == "wb" }
    assert_equal(
      { data_status: "unavailable", reason: "source_unavailable", days_with_data: nil, data_through: nil, listings: [] },
      wb_channel.fetch(:advertising)
    )
    assert_equal(
      { data_status: "unavailable", reason: "source_unavailable" },
      wb_channel.fetch(:search_visibility)
    )
  end

  test "converts advertising and search query failures to channel-level unavailable data" do
    result = ErpAI::V2::MarketingContext.new(
      sku: @sku, period_from: Date.new(2026, 8, 3), period_to: Date.new(2026, 8, 9),
      today: Date.new(2026, 8, 10), time_zone: ActiveSupport::TimeZone["Asia/Shanghai"],
      profitability_context: context_stub({}), platform_products_context: context_stub([]),
      sales_funnel_context: context_stub([]),
      advertising_context: context_error_stub(ActiveRecord::RecordNotFound),
      search_terms_context: context_error_stub(ArgumentError),
      inventory_context: context_stub({}), operations_context: context_stub({})
    ).call

    wb = result.dig(:channel_performance, :weekly).sole.fetch(:channels)
      .find { |channel| channel.fetch(:platform) == "wb" }
    assert_equal({ data_status: "unavailable", reason: "source_unavailable", days_with_data: nil, data_through: nil, listings: [] }, wb.fetch(:advertising))
    assert_equal({ data_status: "unavailable", reason: "source_unavailable" }, wb.fetch(:search_visibility))
  end

  test "does not query a raw account linked to multiple ERP stores" do
    duplicate_store = Ec::Store.create!(
      platform: "wb", store_name: "Marketing WB duplicate #{@token}", company_type: "small",
      wb_raw_account_id: @wb_account.id
    )
    duplicate_product = Ec::SkuProduct.create!(
      sku_code: @sku.sku_code, store: duplicate_store, product_id: "102"
    )
    funnel_calls = []
    advertising_calls = []
    search_calls = []

    result = described_context(
      platform_products: [], funnel: [], advertising: [], search: [], funnel_calls: funnel_calls,
      advertising_calls: advertising_calls, search_calls: search_calls
    )

    wb_channels = result.dig(:channel_performance, :weekly).sole.fetch(:channels)
      .select { |channel| channel.fetch(:platform) == "wb" }
    assert_equal 2, wb_channels.size
    assert wb_channels.all? { |channel| channel[:account_ref].nil? }
    assert wb_channels.all? { |channel| channel[:source_reason] == "duplicate_store_account_mapping" }
    assert_equal [ "ozon:#{@ozon_account.id}" ], funnel_calls.sole.fetch(:store_options).pluck(:ref)
    assert_equal [ @ozon_store.id ], advertising_calls.sole.fetch(:store_ids)
    assert_equal [ @ozon_store.id ], search_calls.sole.fetch(:store_ids)
  ensure
    Ec::SkuProduct.where(id: duplicate_product&.id).delete_all
    Ec::Store.where(id: duplicate_store&.id).delete_all
  end

  test "does not let an inactive duplicate store disable the active channel" do
    inactive_store = Ec::Store.create!(
      platform: "wb", store_name: "Marketing WB inactive duplicate #{@token}", company_type: "small",
      wb_raw_account_id: @wb_account.id, is_active: false
    )
    inactive_product = Ec::SkuProduct.create!(sku_code: @sku.sku_code, store: inactive_store, product_id: "103")
    funnel_calls = []

    result = described_context(
      platform_products: [], funnel: [], advertising: [], search: [], funnel_calls: funnel_calls
    )

    wb_channels = result.dig(:channel_performance, :weekly).sole.fetch(:channels).select do |channel|
      channel.fetch(:platform) == "wb"
    end
    active_channel = wb_channels.find { |channel| channel.fetch(:store_id) == @wb_store.id }
    inactive_channel = wb_channels.find { |channel| channel.fetch(:store_id) == inactive_store.id }
    assert_equal "available", active_channel.fetch(:source_status)
    assert_equal "inactive_store", inactive_channel.fetch(:source_reason)
    assert_equal [ "ozon:#{@ozon_account.id}", "wb:#{@wb_account.id}" ], funnel_calls.sole.fetch(:store_options).pluck(:ref)
  ensure
    Ec::SkuProduct.where(id: inactive_product&.id).delete_all
    Ec::Store.where(id: inactive_store&.id).delete_all
  end

  private

  def described_context(
    platform_products:,
    funnel:,
    advertising:,
    search:,
    funnel_calls: nil,
    advertising_calls: nil,
    search_calls: nil,
    inventory_calls: nil
  )
    ErpAI::V2::MarketingContext.new(
      sku: @sku, period_from: Date.new(2026, 8, 3), period_to: Date.new(2026, 8, 9),
      today: Date.new(2026, 8, 10), time_zone: ActiveSupport::TimeZone["Asia/Shanghai"],
      profitability_context: context_stub({}), platform_products_context: context_stub(platform_products),
      sales_funnel_context: context_stub(funnel, calls: funnel_calls),
      advertising_context: context_stub(advertising, calls: advertising_calls),
      search_terms_context: context_stub(search, calls: search_calls),
      inventory_context: context_stub({}, calls: inventory_calls), operations_context: context_stub({})
    ).call
  end

  def context_stub(result, calls: nil)
    Class.new do
      define_method(:initialize) { |**arguments| calls << arguments if calls }
      define_method(:call) { result }
    end
  end

  def context_error_stub(error)
    Class.new do
      define_method(:initialize) { |**| }
      define_method(:call) { raise error }
    end
  end

  def week_with_stores(*stores)
    { period_from: "2026-08-03", period_to: "2026-08-09", stores: }
  end
end
