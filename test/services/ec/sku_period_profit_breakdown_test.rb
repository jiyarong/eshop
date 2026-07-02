require "test_helper"

class Ec::SkuPeriodProfitBreakdownTest < ActiveSupport::TestCase
  ServiceDouble = Struct.new(:results_rows, :call_count, :results_called) do
    def call
      self.call_count += 1
      self
    end

    def results
      self.results_called = true
      results_rows
    end
  end

  test "aggregates injected wb and ozon attributions for the requested sku" do
    sku = Struct.new(:sku_code).new("Sku-01")

    breakdown = Ec::SkuPeriodProfitBreakdown.new(
      sku: sku,
      from_date: Date.new(2026, 6, 1),
      to_date: Date.new(2026, 6, 30),
      time_zone: ActiveSupport::TimeZone["Asia/Shanghai"],
      wb_attributions: [
        { vendor_code: "sku-01", sales_qty: 3, return_qty: 1, net_qty: 2, pre_tax: BigDecimal("12.50") },
        { vendor_code: "OTHER", sales_qty: 9, return_qty: 9, net_qty: 9, pre_tax: BigDecimal("99.99") }
      ],
      ozon_attributions: [
        { sku_code: "SKU-01", order_count: 4, return_count: 1, net_sales_count: 3, pre_tax_profit: BigDecimal("13.25") },
        { sku_code: "other", order_count: 8, return_count: 8, net_sales_count: 8, pre_tax_profit: BigDecimal("88.88") }
      ]
    ).call

    assert_equal(
      {
        sales_quantity: 3,
        return_quantity: 1,
        net_sales_quantity: 2,
        operating_net_profit_cny: BigDecimal("12.50")
      },
      breakdown.dig(:platforms, :wb)
    )
    assert_equal(
      {
        sales_quantity: 4,
        return_quantity: 1,
        net_sales_quantity: 3,
        operating_net_profit_cny: BigDecimal("13.25")
      },
      breakdown.dig(:platforms, :ozon)
    )
    assert_equal(
      {
        sales_quantity: 7,
        return_quantity: 2,
        net_sales_quantity: 5,
        operating_net_profit_cny: BigDecimal("25.75")
      },
      breakdown[:total]
    )
  end

  test "returns zeroed platform totals when injected attributions are missing" do
    sku = Struct.new(:sku_code).new("Sku-01")

    breakdown = Ec::SkuPeriodProfitBreakdown.new(
      sku: sku,
      from_date: Date.new(2026, 6, 1),
      to_date: Date.new(2026, 6, 30),
      time_zone: ActiveSupport::TimeZone["Asia/Shanghai"]
    ).call

    expected = {
      sales_quantity: 0,
      return_quantity: 0,
      net_sales_quantity: 0,
      operating_net_profit_cny: BigDecimal("0")
    }

    assert_equal expected, breakdown.dig(:platforms, :wb)
    assert_equal expected, breakdown.dig(:platforms, :ozon)
    assert_equal expected, breakdown[:total]
  end

  test "loads wb and ozon attributions from bound stores when injected arrays are absent" do
    wb_service = service_double([
      { vendor_code: "sku-01", sales_qty: 5, return_qty: 1, net_qty: 4, pre_tax: BigDecimal("20.25") },
      { vendor_code: "other", sales_qty: 9, return_qty: 9, net_qty: 9, pre_tax: BigDecimal("99.99") }
    ])
    ozon_service = service_double([
      { sku_code: "SKU-01", order_count: 2, return_count: 1, net_sales_count: 1, pre_tax_profit: BigDecimal("8.75") },
      { sku_code: "other", order_count: 7, return_count: 7, net_sales_count: 7, pre_tax_profit: BigDecimal("77.77") }
    ])

    wb_store = Struct.new(:id, :wb_raw_account_id, :ozon_raw_account_id).new(1, 101, nil)
    ozon_store = Struct.new(:id, :wb_raw_account_id, :ozon_raw_account_id).new(2, nil, 202)
    unbound_store = Struct.new(:id, :wb_raw_account_id, :ozon_raw_account_id).new(3, nil, nil)
    included_association = nil
    bound_products = [
      Struct.new(:store).new(wb_store),
      Struct.new(:store).new(ozon_store),
      Struct.new(:store).new(unbound_store)
    ]
    sku_products_relation = Object.new
    sku_products_relation.define_singleton_method(:includes) do |association|
      included_association = association
      bound_products
    end
    sku = Struct.new(:sku_code, :sku_products).new("Sku-01", sku_products_relation)

    wb_calls = []
    ozon_calls = []
    with_attribution_service_stubs(
      wb_service: wb_service,
      ozon_service: ozon_service,
      wb_calls: wb_calls,
      ozon_calls: ozon_calls
    ) do
      breakdown = Ec::SkuPeriodProfitBreakdown.new(
        sku: sku,
        from_date: Date.new(2026, 6, 1),
        to_date: Date.new(2026, 6, 30),
        time_zone: ActiveSupport::TimeZone["Asia/Shanghai"]
      ).call

      assert_equal :store, included_association
      assert_equal [
        {
          account_id: 101,
          from_date: Date.new(2026, 6, 1),
          to_date: Date.new(2026, 6, 30),
          rate_cny_rub: 11.0,
          rate_byn_rub: 3.5
        }
      ], wb_calls
      assert_equal [
        {
          account_id: 202,
          from_date: Date.new(2026, 6, 1),
          to_date: Date.new(2026, 6, 30)
        }
      ], ozon_calls

      assert_equal(
        {
          sales_quantity: 5,
          return_quantity: 1,
          net_sales_quantity: 4,
          operating_net_profit_cny: BigDecimal("20.25")
        },
        breakdown.dig(:platforms, :wb)
      )
      assert_equal(
        {
          sales_quantity: 2,
          return_quantity: 1,
          net_sales_quantity: 1,
          operating_net_profit_cny: BigDecimal("8.75")
        },
        breakdown.dig(:platforms, :ozon)
      )
      assert_equal(
        {
          sales_quantity: 7,
          return_quantity: 2,
          net_sales_quantity: 5,
          operating_net_profit_cny: BigDecimal("29.0")
        },
        breakdown[:total]
      )
      assert wb_service.results_called
      assert ozon_service.results_called
      assert_equal 1, wb_service.call_count
      assert_equal 1, ozon_service.call_count
    end
  end

  test "nil profit values aggregate as zero without crashing" do
    sku = Struct.new(:sku_code).new("Sku-01")

    breakdown = Ec::SkuPeriodProfitBreakdown.new(
      sku: sku,
      from_date: Date.new(2026, 6, 1),
      to_date: Date.new(2026, 6, 30),
      time_zone: ActiveSupport::TimeZone["Asia/Shanghai"],
      wb_attributions: [
        { vendor_code: "sku-01", sales_qty: 1, return_qty: 0, net_qty: 1, pre_tax: nil }
      ],
      ozon_attributions: [
        { sku_code: "sku-01", order_count: 2, return_count: 0, net_sales_count: 2, pre_tax_profit: nil }
      ]
    ).call

    assert_equal BigDecimal("0"), breakdown.dig(:platforms, :wb, :operating_net_profit_cny)
    assert_equal BigDecimal("0"), breakdown.dig(:platforms, :ozon, :operating_net_profit_cny)
    assert_equal BigDecimal("0"), breakdown.dig(:total, :operating_net_profit_cny)
  end

  test "duplicate bound store bindings only call attribution services once per account" do
    wb_store_1 = Struct.new(:id, :wb_raw_account_id, :ozon_raw_account_id).new(1, 101, nil)
    wb_store_2 = Struct.new(:id, :wb_raw_account_id, :ozon_raw_account_id).new(2, 101, nil)
    ozon_store_1 = Struct.new(:id, :wb_raw_account_id, :ozon_raw_account_id).new(3, nil, 202)
    ozon_store_2 = Struct.new(:id, :wb_raw_account_id, :ozon_raw_account_id).new(4, nil, 202)
    sku = Struct.new(:sku_code, :sku_products).new(
      "Sku-01",
      build_sku_products_relation([
        Struct.new(:store).new(wb_store_1),
        Struct.new(:store).new(wb_store_2),
        Struct.new(:store).new(ozon_store_1),
        Struct.new(:store).new(ozon_store_2)
      ])
    )

    wb_service = service_double([
      { vendor_code: "sku-01", sales_qty: 1, return_qty: 0, net_qty: 1, pre_tax: BigDecimal("3.50") }
    ])
    ozon_service = service_double([
      { sku_code: "sku-01", order_count: 2, return_count: 0, net_sales_count: 2, pre_tax_profit: BigDecimal("4.50") }
    ])
    wb_calls = []
    ozon_calls = []

    with_attribution_service_stubs(
      wb_service: wb_service,
      ozon_service: ozon_service,
      wb_calls: wb_calls,
      ozon_calls: ozon_calls
    ) do
      breakdown = Ec::SkuPeriodProfitBreakdown.new(
        sku: sku,
        from_date: Date.new(2026, 6, 1),
        to_date: Date.new(2026, 6, 30),
        time_zone: ActiveSupport::TimeZone["Asia/Shanghai"]
      ).call

      assert_equal 1, wb_service.call_count
      assert_equal 1, ozon_service.call_count
      assert_equal 1, wb_calls.size
      assert_equal 1, ozon_calls.size
      assert_equal BigDecimal("8.0"), breakdown.dig(:total, :operating_net_profit_cny)
    end
  end

  test "counts wb and ozon rows via bound platform identifiers when sku code does not match" do
    wb_store = Struct.new(:id, :wb_raw_account_id, :ozon_raw_account_id).new(1, 101, nil)
    ozon_store = Struct.new(:id, :wb_raw_account_id, :ozon_raw_account_id).new(2, nil, 202)
    wb_product = Struct.new(:store, :platform, :product_id, :platform_sku_id).new(wb_store, "wb", 555, nil)
    ozon_product = Struct.new(:store, :platform, :product_id, :platform_sku_id).new(ozon_store, "ozon", nil, "OZ-777")
    sku = Struct.new(:sku_code, :sku_products).new(
      "Sku-01",
      build_sku_products_relation([wb_product, ozon_product])
    )

    breakdown = Ec::SkuPeriodProfitBreakdown.new(
      sku: sku,
      from_date: Date.new(2026, 6, 1),
      to_date: Date.new(2026, 6, 30),
      time_zone: ActiveSupport::TimeZone["Asia/Shanghai"],
      wb_attributions: [
        { vendor_code: "different-code", nm_id: 555, sales_qty: 3, return_qty: 1, net_qty: 2, pre_tax: BigDecimal("10.50") }
      ],
      ozon_attributions: [
        { sku_code: "different-code", ozon_sku_id: "OZ-777", order_count: 4, return_count: 1, net_sales_count: 3, pre_tax_profit: BigDecimal("11.25") }
      ]
    ).call

    assert_equal 3, breakdown.dig(:platforms, :wb, :sales_quantity)
    assert_equal BigDecimal("10.50"), breakdown.dig(:platforms, :wb, :operating_net_profit_cny)
    assert_equal 4, breakdown.dig(:platforms, :ozon, :sales_quantity)
    assert_equal BigDecimal("11.25"), breakdown.dig(:platforms, :ozon, :operating_net_profit_cny)
    assert_equal 7, breakdown.dig(:total, :sales_quantity)
    assert_equal BigDecimal("21.75"), breakdown.dig(:total, :operating_net_profit_cny)
  end

  test "distinct stores sharing a raw account id only fetch attribution once per account" do
    wb_store_1 = Struct.new(:id, :wb_raw_account_id, :ozon_raw_account_id).new(1, 101, nil)
    wb_store_2 = Struct.new(:id, :wb_raw_account_id, :ozon_raw_account_id).new(2, 101, nil)
    ozon_store_1 = Struct.new(:id, :wb_raw_account_id, :ozon_raw_account_id).new(3, nil, 202)
    ozon_store_2 = Struct.new(:id, :wb_raw_account_id, :ozon_raw_account_id).new(4, nil, 202)
    sku = Struct.new(:sku_code, :sku_products).new(
      "Sku-01",
      build_sku_products_relation([
        Struct.new(:store).new(wb_store_1),
        Struct.new(:store).new(wb_store_2),
        Struct.new(:store).new(ozon_store_1),
        Struct.new(:store).new(ozon_store_2)
      ])
    )

    wb_service = service_double([{ vendor_code: "sku-01", sales_qty: 1, return_qty: 0, net_qty: 1, pre_tax: BigDecimal("3.50") }])
    ozon_service = service_double([{ sku_code: "sku-01", order_count: 2, return_count: 0, net_sales_count: 2, pre_tax_profit: BigDecimal("4.50") }])
    wb_calls = []
    ozon_calls = []

    with_attribution_service_stubs(
      wb_service: wb_service,
      ozon_service: ozon_service,
      wb_calls: wb_calls,
      ozon_calls: ozon_calls
    ) do
      Ec::SkuPeriodProfitBreakdown.new(
        sku: sku,
        from_date: Date.new(2026, 6, 1),
        to_date: Date.new(2026, 6, 30),
        time_zone: ActiveSupport::TimeZone["Asia/Shanghai"]
      ).call

      assert_equal [101], wb_calls.map { |call| call[:account_id] }
      assert_equal [202], ozon_calls.map { |call| call[:account_id] }
      assert_equal 1, wb_service.call_count
      assert_equal 1, ozon_service.call_count
    end
  end

  private

  def service_double(results_rows)
    ServiceDouble.new(results_rows, 0, false)
  end

  def build_sku_products_relation(bound_products)
    Object.new.tap do |relation|
      relation.define_singleton_method(:includes) do |_association|
        bound_products
      end
    end
  end

  def with_attribution_service_stubs(wb_service:, ozon_service:, wb_calls:, ozon_calls:)
    original_wb_new = Ec::WbProfitAttribution.method(:new)
    original_ozon_new = Ec::OzonProfitAttribution.method(:new)

    Ec::WbProfitAttribution.define_singleton_method(:new, ->(**kwargs) {
      wb_calls << kwargs
      wb_service
    })
    Ec::OzonProfitAttribution.define_singleton_method(:new, ->(**kwargs) {
      ozon_calls << kwargs
      ozon_service
    })

    yield
  ensure
    Ec::WbProfitAttribution.define_singleton_method(:new, original_wb_new)
    Ec::OzonProfitAttribution.define_singleton_method(:new, original_ozon_new)
  end
end
