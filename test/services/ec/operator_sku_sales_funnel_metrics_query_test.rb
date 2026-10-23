require "test_helper"

class Ec::OperatorSkuSalesFunnelMetricsQueryTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(5).upcase
    @skus = 2.times.map { |index| Ec::Sku.create!(sku_code: "OP-FUNNEL-#{index}-#{@token}") }
    @account = RawWb::SellerAccount.create!(name: "WB #{@token}", api_token: "token-#{@token}", company_type: :small)
    @store = Ec::Store.create!(platform: "wb", store_name: "WB #{@token}", company_type: "small", wb_raw_account_id: @account.id)
    @products = @skus.each_with_index.map do |sku, index|
      Ec::SkuProduct.create!(sku_code: sku.sku_code, store: @store, product_id: (91_000 + index).to_s)
    end
  end

  teardown do
    Ec::OrderItem.where(store_id: @store&.id).delete_all
    Ec::OrderFulfillment.where(store_id: @store&.id).delete_all
    version_ids = Ec::SkuProfitVersion.where(sku_id: @skus&.map(&:id)).pluck(:id)
    context_ids = Ec::SkuProfitVersionContext.where(sku_profit_version_id: version_ids).pluck(:id)
    Ec::OperationLog.where(record_type: "Ec::SkuProfitVersionContext", record_id: context_ids).delete_all
    Ec::OperationLog.where(record_type: "Ec::SkuProfitVersion", record_id: version_ids).delete_all
    Ec::SkuProfitVersionContext.where(id: context_ids).delete_all
    Ec::SkuProfitVersion.where(id: version_ids).delete_all
    Ec::Order.where(store_id: @store&.id).delete_all
    RawWb::SalesFunnelDaily.where(account_id: @account&.id).delete_all
    Ec::SkuProduct.where(id: @products&.map(&:id)).delete_all
    Ec::Store.where(id: @store&.id).delete_all
    Ec::Sku.with_deleted.where(id: @skus&.map(&:id)).delete_all
    @account&.destroy!
  end

  test "loads multiple skus in a fixed number of queries and compares natural weeks" do
    @products.each_with_index do |product, index|
      create_funnel(product, Date.new(2026, 8, 25), views: 100, carts: 20, orders: 10, cancellations: 1)
      create_funnel(product, Date.new(2026, 9, 1), views: 120 + index, carts: 30, orders: 15, cancellations: 2)
      create_order(product, Date.new(2026, 9, 1), "delivered", 6 + index)
    end

    sql_count = 0
    callback = lambda do |_name, _started, _finished, _id, payload|
      sql_count += 1 unless payload[:name].in?(%w[SCHEMA CACHE]) || payload[:cached]
    end
    result = ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { query.call }

    first = result.fetch(@skus.first)
    assert_equal BigDecimal("120"), first.dig(:product_card_views, :value)
    assert_equal BigDecimal("20"), first.dig(:product_card_views, :comparison, :delta_pct)
    assert_equal BigDecimal("25"), first.dig(:cart_rate, :value)
    assert_equal BigDecimal("2"), first.dig(:cancellations, :value)
    assert_equal "negative", first.dig(:cancellations, :comparison, :semantic)
    assert_equal 6, first.dig(:conversions, :value)
    assert_equal 6, first.dig(:net_sales, :value)
    assert_operator sql_count, :<=, 5
  end

  test "estimates profit for the selected week from the order table and the profit version, in a fixed number of queries" do
    first_product = @products.first
    create_order(first_product, Date.new(2026, 9, 1), "delivered", 6, fulfillment_type: "fbw", key: "a")
    create_order(first_product, Date.new(2026, 9, 2), "returned", 1, fulfillment_type: "fbs", key: "b")
    create_order(first_product, Date.new(2026, 9, 3), "cancelled", 2, fulfillment_type: "fbw", key: "c")
    create_order(first_product, Date.new(2026, 8, 25), "delivered", 50, fulfillment_type: "fbw", key: "previous-week")
    create_order(first_product, Date.new(2026, 9, 4), "delivered", 3, fulfillment_type: "fbs", key: "e")
    @skus.each { |sku| create_version(sku, fbo_profit: 10, fbs_profit: 4) }

    counts = {}
    [ [ @skus.first ], @skus ].each do |skus|
      sql_count = 0
      callback = lambda do |_name, _started, _finished, _id, payload|
        sql_count += 1 unless payload[:name].in?(%w[SCHEMA CACHE]) || payload[:cached]
      end
      result = ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { query_for(skus).call }
      counts[skus.size] = sql_count
      @result = result
    end

    estimate = @result.fetch(@skus.first).fetch(:profit_estimate)
    orders = estimate.dig(:bases, :orders)
    conversions = estimate.dig(:bases, :conversions)
    # Ordered in the week: 6 FBW + 1 FBS + 2 FBW (cancelled still counts as ordered) + 3 FBS.
    assert_equal 12, orders.fetch(:units)
    assert_equal 8 * 10 + 4 * 4, orders.fetch(:profit_cny)
    # Completed or returned: 6 FBW + 1 FBS + 3 FBS.
    assert_equal 10, conversions.fetch(:units)
    assert_equal 6 * 10 + 4 * 4, conversions.fetch(:profit_cny)
    assert_equal "draft", estimate.dig(:version, :status)
    assert_equal "manual", estimate.dig(:version, :kind)
    # Profit per priced unit, the figure the workbench shows beside the totals.
    assert_equal (8 * 10 + 4 * 4).to_d / 12, orders.fetch(:unit_average_cny)
    assert_equal (6 * 10 + 4 * 4).to_d / 10, conversions.fetch(:unit_average_cny)
    # Every version of the SKU comes with its own estimate, for the version switch.
    options = estimate.fetch(:options)
    assert_equal 1, options.size
    assert_equal estimate.dig(:version, :id), options.first.dig(:version, :id)
    assert_equal orders.fetch(:profit_cny), options.first.dig(:bases, :orders, :profit_cny)
    assert_equal 0, @result.fetch(@skus.last).dig(:profit_estimate, :bases, :orders, :units)
    assert_operator counts.fetch(2), :<=, counts.fetch(1), "query count must not grow with the number of SKUs"
    assert_operator counts.fetch(2), :<=, 7
  end

  test "carries the estimate under each of the SKU's versions, automatic ones included" do
    first_product = @products.first
    create_order(first_product, Date.new(2026, 9, 1), "delivered", 6, fulfillment_type: "fbw", key: "a")
    create_order(first_product, Date.new(2026, 9, 4), "delivered", 3, fulfillment_type: "fbs", key: "e")
    sku = @skus.first
    create_version(sku, fbo_profit: 10, fbs_profit: 4)
    automatic = sku.profit_versions.new(
      name: "2026-09", kind: "automatic", status: "published", effective_from: Date.new(2026, 9, 1), effective_to: Date.new(2026, 9, 30),
      data_from: Date.new(2026, 8, 3), data_to: Date.new(2026, 8, 30)
    )
    { "fbo" => 20, "fbs" => 8 }.each do |mode, profit|
      automatic.contexts.build(platform: "wb", market: "ru", delivery_mode: mode, warehouse_region: "main",
        company_type: "small", calculation_status: "valid", profit_cny: profit)
    end
    automatic.system_write = true
    automatic.save!

    options = query_for([ sku ]).call.fetch(sku).dig(:profit_estimate, :options)

    # The newest automatic version is the default; the manual one stays one pick away.
    estimate = query_for([ sku ]).call.fetch(sku).fetch(:profit_estimate)
    assert_equal "automatic", estimate.dig(:version, :kind)
    assert_equal 6 * 20 + 3 * 8, estimate.dig(:bases, :orders, :profit_cny)

    by_kind = options.index_by { |option| option.dig(:version, :kind) }
    assert_equal %w[automatic manual], by_kind.keys.sort
    assert_equal 6 * 10 + 3 * 4, by_kind.fetch("manual").dig(:bases, :orders, :profit_cny)
    assert_equal 6 * 20 + 3 * 8, by_kind.fetch("automatic").dig(:bases, :orders, :profit_cny)
    assert_equal (6 * 20 + 3 * 8).to_d / 9, by_kind.fetch("automatic").dig(:bases, :orders, :unit_average_cny)
    assert_equal "2026-09", by_kind.fetch("automatic").dig(:version, :name)
  end

  test "adds Ozon cancellations into the same operator sku funnel metric" do
    account = RawOzon::SellerAccount.create!(
      company_name: "Ozon #{@token}", client_id: "ozon-#{@token}", api_key: "key-#{@token}", company_type: :small
    )
    store = Ec::Store.create!(
      platform: "ozon", store_name: "Ozon #{@token}", company_type: "small", ozon_raw_account_id: account.id
    )
    product = Ec::SkuProduct.create!(
      sku_code: @skus.first.sku_code, store: store, product_id: "OZ-#{@token}", platform_sku_id: "81001"
    )
    RawOzon::SalesFunnelDaily.create!(
      account: account, stat_date: Date.new(2026, 8, 25), sku: 81_001,
      hits_view_pdp: 100, hits_tocart_pdp: 20, ordered_units: 10, cancellations: 1,
      synced_at: Time.current
    )
    RawOzon::SalesFunnelDaily.create!(
      account: account, stat_date: Date.new(2026, 9, 1), sku: 81_001,
      hits_view_pdp: 120, hits_tocart_pdp: 30, ordered_units: 15, cancellations: 3,
      synced_at: Time.current
    )

    result = query_for([@skus.first]).call.fetch(@skus.first)

    assert_equal BigDecimal("3"), result.dig(:cancellations, :value)
    assert_equal BigDecimal("200"), result.dig(:cancellations, :comparison, :delta_pct)
    assert_equal "negative", result.dig(:cancellations, :comparison, :semantic)
  ensure
    RawOzon::SalesFunnelDaily.where(account_id: account&.id).delete_all
    Ec::SkuProduct.where(id: product&.id).delete_all
    Ec::Store.where(id: store&.id).delete_all
    RawOzon::SellerAccount.where(id: account&.id).delete_all
  end

  test "aggregates bound products and both week boundaries without loading daily records" do
    @products.each do |product|
      create_funnel(product, Date.new(2026, 8, 23), views: 999, carts: 999, orders: 999, cancellations: 999)
      create_funnel(product, Date.new(2026, 8, 24), views: 20, carts: 10, orders: 4, cancellations: 1)
      create_funnel(product, Date.new(2026, 8, 30), views: 30, carts: 10, orders: 6, cancellations: 1)
      create_funnel(product, Date.new(2026, 8, 31), views: 40, carts: 10, orders: 6, cancellations: 2)
      create_funnel(product, Date.new(2026, 9, 6), views: 60, carts: 20, orders: 9, cancellations: 1)
      create_funnel(product, Date.new(2026, 9, 7), views: 999, carts: 999, orders: 999, cancellations: 999)
    end
    RawWb::SalesFunnelDaily.create!(account: @account, stat_date: Date.new(2026, 9, 1), nm_id: 99_999,
      open_card: 999, orders: 999, synced_at: Time.current)
    counts = []
    loaded_daily_records = 0
    instantiation = lambda do |*args|
      payload = args.last
      loaded_daily_records += payload[:record_count] if payload[:class_name].in?(%w[RawWb::SalesFunnelDaily RawOzon::SalesFunnelDaily])
    end

    ActiveRecord::Base.uncached do
      ActiveSupport::Notifications.subscribed(instantiation, "instantiation.active_record") do
        [ [ @skus.first ], @skus ].each do |skus|
          sql_count = 0
          callback = ->(*args) { sql_count += 1 unless args.last[:cached] || args.last[:name].in?(%w[SCHEMA TRANSACTION]) }
          result = ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { query_for(skus).call }
          skus.each do |sku|
            metrics = result.fetch(sku)
            assert_equal 100, metrics.dig(:product_card_views, :value)
            assert_equal 100, metrics.dig(:product_card_views, :comparison, :delta_pct)
            assert_equal 30, metrics.dig(:cart_additions, :value)
            assert_equal 15, metrics.dig(:orders, :value)
            assert_equal 3, metrics.dig(:cancellations, :value)
          end
          counts << sql_count
        end
      end
    end

    assert_equal 0, loaded_daily_records
    assert_equal counts.first, counts.last, "query count must not grow with the number of SKUs"
  end

  private

  def query
    query_for(@skus)
  end

  def query_for(skus)
    Ec::OperatorSkuSalesFunnelMetricsQuery.new(
      skus: skus, from_date: Date.new(2026, 8, 31), to_date: Date.new(2026, 9, 6),
      time_zone: Time.find_zone!("Asia/Shanghai")
    )
  end

  def create_funnel(product, date, views:, carts:, orders:, cancellations:)
    RawWb::SalesFunnelDaily.create!(
      account: @account, stat_date: date, nm_id: product.product_id,
      open_card: views, add_to_cart: carts, orders:, cancel_count: cancellations,
      synced_at: Time.current
    )
  end

  def create_order(product, date, status, quantity, fulfillment_type: nil, key: nil)
    order = Ec::Order.create!(
      store: @store, platform: "wb", order_key: "#{product.product_id}-#{date}-#{key}-#{@token}",
      order_status: status, ordered_at: Time.find_zone!("Asia/Shanghai").local(date.year, date.month, date.day, 12),
      buyer_country: "RU"
    )
    fulfillment = if fulfillment_type
      Ec::OrderFulfillment.create!(order:, store: @store, platform: "wb", fulfillment_type:, status: "delivered",
        external_fulfillment_id: "f-#{order.order_key}", fulfillment_key: "f-#{order.order_key}")
    end
    Ec::OrderItem.create!(order:, store: @store, platform: "wb", platform_sku_id: product.product_id, quantity:,
      fulfillment_id: fulfillment&.id)
  end

  def create_version(sku, fbo_profit:, fbs_profit:)
    version = sku.profit_versions.new(name: "Estimate #{@token}", status: "draft", effective_from: Date.new(2026, 8, 1))
    { "fbo" => fbo_profit, "fbs" => fbs_profit }.each do |mode, profit|
      version.contexts.build(platform: "wb", market: "ru", delivery_mode: mode, warehouse_region: "main",
        company_type: "small", calculation_status: "valid", profit_cny: profit)
    end
    version.save!
  end
end
