require "test_helper"

class Ec::SkuOperationActionMetricsQueryTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(5).upcase
    @time_zone = Time.find_zone!("Asia/Shanghai")
    @account = RawWb::SellerAccount.create!(
      name: "Action metrics #{@token}",
      api_token: "token-#{@token}",
      company_type: "small"
    )
    @store = Ec::Store.create!(
      platform: "wb",
      store_name: "Action metrics #{@token}",
      company_type: "small",
      wb_raw_account_id: @account.id,
      is_active: true
    )
    @sku = Ec::Sku.create!(sku_code: "ACTION-METRICS-#{@token}", product_name: "Action metrics")
    @wrong_sku = Ec::Sku.create!(sku_code: "ACTION-WRONG-#{@token}", product_name: "Wrong")
    @product = Ec::SkuProduct.create!(
      sku: @sku,
      store: @store,
      product_id: "#{900_000_000 + rand(10_000)}"
    )
  end

  teardown do
    Ec::Snapshot.where(snapshot_type: Ec::InventorySnapshot.snapshot_type, sku_id: @sku&.id).delete_all
    RawWb::SalesFunnelDaily.where(account_id: @account&.id).delete_all
    Ec::SkuProduct.where(id: @product&.id).delete_all
    Ec::Sku.with_deleted.where(id: [ @sku&.id, @wrong_sku&.id ].compact).delete_all
    Ec::Store.where(id: @store&.id).delete_all
    RawWb::SellerAccount.where(id: @account&.id).delete_all
  end

  test "returns store weekly profit metrics, inventory snapshots, and WB funnel metrics" do
    week_start = Date.new(2026, 7, 20)
    date = week_start + 2.days
    RawWb::SalesFunnelDaily.create!(
      account: @account,
      stat_date: date,
      nm_id: @product.product_id,
      open_card: 40,
      add_to_cart: 10,
      orders: 4,
      orders_sum: 800,
      synced_at: Time.current
    )
    Ec::Snapshot.create!(
      snapshot_type: Ec::InventorySnapshot.snapshot_type,
      snapshot_date: week_start + 5.days,
      sku: @sku,
      content: {
        overview: {
          book_stock: 80,
          platform_stock: 35,
          platform_inbound_stock: 6,
          available_stock: 39,
          out_of_stock: false
        },
        distribution: {
          levels: [
            {
              store_id: @store.id,
              platform: "wb",
              account_id: @account.id,
              fulfillment_type: "fbw",
              quantity: 35
            },
            {
              store_id: @store.id,
              platform: "wb",
              account_id: @account.id,
              fulfillment_type: "inbound",
              quantity: 6
            }
          ]
        }
      }
    )
    requests = []
    profit_runner = lambda do |params:, today:|
      requests << { params: params, today: today }
      {
        rows: [
          {
            sales_qty: 5,
            return_qty: 1,
            net_qty: 4,
            retail_amount: 500,
            settlement: 420,
            delivery: 20,
            storage: 8,
            ad: 30,
            goods_cost: 100,
            pre_tax: 262,
            tax: 15,
            after_tax: 247
          }
        ]
      }
    end

    result = Ec::SkuOperationActionMetricsQuery.new(
      sku: @sku,
      from_date: week_start,
      to_date: week_start + 6.days,
      time_zone: @time_zone,
      profit_report_runner: profit_runner
    ).call

    assert_not result.key?(:sales_by_day_and_platform)
    assert_equal [ @sku.sku_code ], requests.sole.dig(:params, :sku_codes)
    assert_equal "wb:#{@account.id}", requests.sole.dig(:params, :store_ref)
    assert_equal "BYN", result.dig(:stores, @store.id, :currency)
    profit = result.dig(:weekly_profit_by_week_and_store, [ week_start, @store.id ])
    assert_equal 5, profit.fetch(:sales_quantity)
    assert_equal 4, profit.fetch(:net_sales_quantity)
    assert_equal 30, profit.fetch(:advertising_cost)
    assert_equal 247, profit.fetch(:after_tax_profit)
    inventory = result.dig(:inventory_snapshots_by_week, week_start)
    assert_equal "2026-07-25", inventory.fetch(:snapshot_date)
    assert_equal 80, inventory.dig(:sku, :book_stock)
    assert_equal 35, inventory.dig(:stores, @store.id, :platform_stock)
    assert_equal 6, inventory.dig(:stores, @store.id, :inbound_quantity)
    funnel = result.dig(:funnel_by_day_and_platform, [ date, "wb" ])
    assert_equal 40, funnel.fetch(:views).to_i
    assert_equal 10, funnel.fetch(:add_to_cart).to_i
    assert_equal 4, funnel.fetch(:funnel_orders).to_i
    assert_equal 800, funnel.fetch(:revenue).to_i
  end

  test "normalizes Ozon weekly profit costs and daily funnel metrics" do
    week_start = Date.new(2026, 7, 20)
    date = week_start + 2.days
    ozon_account = RawOzon::SellerAccount.create!(
      company_name: "Action metrics Ozon #{@token}",
      client_id: "ozon-#{@token}",
      api_key: "key-#{@token}",
      company_type: "small"
    )
    ozon_store = Ec::Store.create!(
      platform: "ozon",
      store_name: "Action metrics Ozon #{@token}",
      company_type: "small",
      ozon_raw_account_id: ozon_account.id,
      is_active: true
    )
    ozon_product = Ec::SkuProduct.create!(
      sku: @sku,
      store: ozon_store,
      product_id: "OZON-PRODUCT-#{@token}",
      platform_sku_id: "#{700_000_000 + rand(10_000)}"
    )
    RawOzon::SalesFunnelDaily.create!(
      account: ozon_account,
      stat_date: date,
      sku: ozon_product.platform_sku_id,
      hits_view: 50,
      session_view: 30,
      hits_tocart: 8,
      ordered_units: 5,
      revenue: 1_200,
      returns_count: 1,
      synced_at: Time.current
    )

    result = Ec::SkuOperationActionMetricsQuery.new(
      sku: @sku,
      from_date: week_start,
      to_date: week_start + 6.days,
      time_zone: @time_zone,
      profit_report_runner: lambda do |**|
        {
          rows: [
            {
              order_count: 6,
              return_count: 1,
              net_sales_count: 5,
              sales_revenue: 1_200,
              commission: -180,
              delivery_charge: -90,
              storage_fee: -20,
              total_ad_cost: -120,
              goods_cost: -300,
              pre_tax_profit: 490,
              after_tax_profit: 420
            }
          ]
        }
      end
    ).call
    funnel = result.dig(:funnel_by_day_and_platform, [ date, "ozon" ])
    profit = result.dig(:weekly_profit_by_week_and_store, [ week_start, ozon_store.id ])

    assert_equal 5, profit.fetch(:net_sales_quantity)
    assert_equal 120, profit.fetch(:advertising_cost)
    assert_equal 300, profit.fetch(:goods_cost)
    assert_equal 35, profit.fetch(:after_tax_margin_pct)
    assert_equal 50, funnel.fetch(:views).to_i
    assert_equal 30, funnel.fetch(:sessions).to_i
    assert_equal 8, funnel.fetch(:add_to_cart).to_i
    assert_equal 5, funnel.fetch(:funnel_orders).to_i
    assert_equal 1, funnel.fetch(:returns).to_i
  ensure
    RawOzon::SalesFunnelDaily.where(account_id: ozon_account&.id).delete_all
    Ec::SkuProduct.where(id: ozon_product&.id).delete_all
    Ec::Store.where(id: ozon_store&.id).delete_all
    RawOzon::SellerAccount.where(id: ozon_account&.id).delete_all
  end

  test "marks a weekly profit report unavailable instead of using another sales source" do
    week_start = Date.new(2026, 7, 20)
    result = Ec::SkuOperationActionMetricsQuery.new(
      sku: @sku,
      from_date: week_start,
      to_date: week_start + 6.days,
      time_zone: @time_zone,
      profit_report_runner: ->(**) { raise ArgumentError, "missing_weekly_rate" }
    ).call

    assert_nil result.dig(:weekly_profit_by_week_and_store, [ week_start, @store.id ])
    assert_not result.key?(:sales_by_day_and_platform)
  end
end
