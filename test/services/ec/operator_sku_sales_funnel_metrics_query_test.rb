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

  def create_order(product, date, status, quantity)
    order = Ec::Order.create!(
      store: @store, platform: "wb", order_key: "#{product.product_id}-#{date}-#{@token}",
      order_status: status, ordered_at: Time.find_zone!("Asia/Shanghai").local(date.year, date.month, date.day, 12)
    )
    Ec::OrderItem.create!(order:, store: @store, platform: "wb", platform_sku_id: product.product_id, quantity:)
  end
end
