require "test_helper"

class Ec::SkuPeriodRoiQueryTest < ActiveSupport::TestCase
  setup do
    @token = "sku-period-roi-#{SecureRandom.hex(4)}"
    @sku_code = "ROI-#{@token}".upcase
  end

  teardown do
    Ec::SkuCost.where(sku_code: @sku_code).delete_all
    Ec::Sku.with_deleted.where(sku_code: @sku_code).delete_all
  end

  test "returns total and per-platform roi payload using sku goods cost and predicted holding costs" do
    sku = Ec::Sku.create!(sku_code: @sku_code)
    Ec::SkuCost.create!(
      sku_code: sku.sku_code,
      purchase_price_cny: BigDecimal("20"),
      freight_to_by_cny: BigDecimal("5"),
      customs_misc_cny: BigDecimal("3"),
      customs_duty_rate: BigDecimal("0.1"),
      import_vat_rate: BigDecimal("0.2"),
      pkg_length_cm: BigDecimal("10"),
      pkg_width_cm: BigDecimal("20"),
      pkg_height_cm: BigDecimal("6")
    )

    breakdown_payload = {
      total: {
        sales_quantity: 12,
        return_quantity: 2,
        net_sales_quantity: 10,
        operating_net_profit_cny: BigDecimal("500")
      },
      platforms: {
        wb: {
          sales_quantity: 9,
          return_quantity: 1,
          net_sales_quantity: 8,
          operating_net_profit_cny: BigDecimal("320")
        },
        ozon: {
          sales_quantity: 3,
          return_quantity: 1,
          net_sales_quantity: 2,
          operating_net_profit_cny: BigDecimal("180")
        }
      }
    }

    constructor_calls = []

    with_stubbed_constructor(Ec::SkuPeriodProfitBreakdown, lambda { |**kwargs|
      constructor_calls << kwargs
      Struct.new(:call).new(breakdown_payload)
    }) do
      result = Ec::SkuPeriodRoiQuery.new(
        sku_code: sku.sku_code,
        from_date: Date.new(2026, 6, 1),
        to_date: Date.new(2026, 6, 10),
        time_zone: "Asia/Shanghai"
      ).call

      assert_equal 10, result[:days_count]
      assert_equal BigDecimal("34.4000"), result[:unit_goods_cost_cny]
      assert_equal BigDecimal("1.2000"), result[:unit_volume_l]
      assert_equal "adjusted_operating_net_profit_cny / cost_base_cny", result[:roi_formula]
      assert_equal false, result[:missing_cost]
      assert_equal false, result[:missing_volume]
      assert_equal true, result[:calculable]

      assert_equal(
        {
          sales_quantity: 12,
          return_quantity: 2,
          net_sales_quantity: 10,
          average_daily_net_sales: BigDecimal("1.0"),
          projected_stock_qty_180d: BigDecimal("180.0"),
          average_inventory_qty: BigDecimal("90.0"),
          projected_months_to_clear: BigDecimal("5.93863411415374463873309138898060046189376443418"),
          projected_unit_profit_cny: BigDecimal("50.0"),
          projected_operating_net_profit_cny: BigDecimal("9000.0"),
          predicted_storage_cost_cny: BigDecimal("64.137248432860442098317387000990484988452655889144"),
          predicted_interest_cost_cny: BigDecimal("183.8601121741999340151765094028393903002309468822128"),
          cost_base_cny: BigDecimal("6192.0"),
          operating_net_profit_cny: BigDecimal("500"),
          adjusted_operating_net_profit_cny: BigDecimal("8752.0026393929396238865061035961701247113163972286432"),
          roi: BigDecimal("8752.0026393929396238865061035961701247113163972286432") / BigDecimal("6192")
        },
        result[:total]
      )

      assert_equal(
        {
          sales_quantity: 9,
          return_quantity: 1,
          net_sales_quantity: 8,
          average_daily_net_sales: BigDecimal("0.8"),
          projected_stock_qty_180d: BigDecimal("144.0"),
          average_inventory_qty: BigDecimal("72.0"),
          projected_months_to_clear: BigDecimal("5.93863411415374463873309138898060046189376443418"),
          projected_unit_profit_cny: BigDecimal("40.0"),
          projected_operating_net_profit_cny: BigDecimal("5760.0"),
          predicted_storage_cost_cny: BigDecimal("51.3097987462883536786539096007923879907621247113152"),
          predicted_interest_cost_cny: BigDecimal("147.08808973935994721214120752227151224018475750577024"),
          cost_base_cny: BigDecimal("4953.6"),
          operating_net_profit_cny: BigDecimal("320"),
          adjusted_operating_net_profit_cny: BigDecimal("5561.60211151435169910920488287693609976905311778291456"),
          roi: BigDecimal("5561.60211151435169910920488287693609976905311778291456") / BigDecimal("4953.6")
        },
        result.dig(:platforms, :wb)
      )

      assert_equal(
        {
          sales_quantity: 3,
          return_quantity: 1,
          net_sales_quantity: 2,
          average_daily_net_sales: BigDecimal("0.2"),
          projected_stock_qty_180d: BigDecimal("36.0"),
          average_inventory_qty: BigDecimal("18.0"),
          projected_months_to_clear: BigDecimal("5.93863411415374463873309138898060046189376443418"),
          projected_unit_profit_cny: BigDecimal("90.0"),
          projected_operating_net_profit_cny: BigDecimal("3240.0"),
          predicted_storage_cost_cny: BigDecimal("12.8274496865720884196634774001980969976905311778288"),
          predicted_interest_cost_cny: BigDecimal("36.77202243483998680303530188056787806004618937644256"),
          cost_base_cny: BigDecimal("1238.4"),
          operating_net_profit_cny: BigDecimal("180"),
          adjusted_operating_net_profit_cny: BigDecimal("3190.40052787858792477730122071923402494226327944572864"),
          roi: BigDecimal("3190.40052787858792477730122071923402494226327944572864") / BigDecimal("1238.4")
        },
        result.dig(:platforms, :ozon)
      )
    end

    assert_equal 1, constructor_calls.size
    assert_equal sku, constructor_calls.first[:sku]
    assert_equal Date.new(2026, 6, 1), constructor_calls.first[:from_date]
    assert_equal Date.new(2026, 6, 10), constructor_calls.first[:to_date]
    assert_equal ActiveSupport::TimeZone["Asia/Shanghai"], constructor_calls.first[:time_zone]
  end

  test "marks payload as missing cost when sku standard cost is unavailable" do
    sku = Ec::Sku.create!(sku_code: @sku_code)
    breakdown_payload = {
      total: {
        sales_quantity: 5,
        return_quantity: 1,
        net_sales_quantity: 4,
        operating_net_profit_cny: BigDecimal("120")
      },
      platforms: {
        wb: {
          sales_quantity: 5,
          return_quantity: 1,
          net_sales_quantity: 4,
          operating_net_profit_cny: BigDecimal("120")
        },
        ozon: {
          sales_quantity: 0,
          return_quantity: 0,
          net_sales_quantity: 0,
          operating_net_profit_cny: BigDecimal("0")
        }
      }
    }

    with_stubbed_constructor(Ec::SkuPeriodProfitBreakdown, lambda { |**|
      Struct.new(:call).new(breakdown_payload)
    }) do
      result = Ec::SkuPeriodRoiQuery.new(
        sku_code: sku.sku_code,
        from_date: Date.new(2026, 6, 1),
        to_date: Date.new(2026, 6, 5),
        time_zone: ActiveSupport::TimeZone["Asia/Shanghai"]
      ).call

      assert_nil result[:unit_goods_cost_cny]
      assert_equal true, result[:missing_cost]
      assert_equal false, result[:missing_volume]
      assert_equal false, result[:calculable]
      assert_nil result[:unit_volume_l]
      assert_nil result.dig(:total, :predicted_storage_cost_cny)
      assert_nil result.dig(:total, :predicted_interest_cost_cny)
      assert_nil result.dig(:total, :adjusted_operating_net_profit_cny)
      assert_nil result.dig(:total, :cost_base_cny)
      assert_nil result.dig(:total, :roi)
      assert_nil result.dig(:platforms, :wb, :cost_base_cny)
      assert_nil result.dig(:platforms, :wb, :roi)
    end
  end

  test "returns non calculable payload for an invalid date range" do
    sku = Ec::Sku.create!(sku_code: @sku_code)
    Ec::SkuCost.create!(
      sku_code: sku.sku_code,
      purchase_price_cny: BigDecimal("20"),
      freight_to_by_cny: BigDecimal("5"),
      customs_misc_cny: BigDecimal("3"),
      customs_duty_rate: BigDecimal("0.1"),
      import_vat_rate: BigDecimal("0.2"),
      pkg_length_cm: BigDecimal("10"),
      pkg_width_cm: BigDecimal("20"),
      pkg_height_cm: BigDecimal("6")
    )

    breakdown_payload = {
      total: {
        sales_quantity: 5,
        return_quantity: 1,
        net_sales_quantity: 4,
        operating_net_profit_cny: BigDecimal("120")
      },
      platforms: {
        wb: {
          sales_quantity: 5,
          return_quantity: 1,
          net_sales_quantity: 4,
          operating_net_profit_cny: BigDecimal("120")
        },
        ozon: {
          sales_quantity: 0,
          return_quantity: 0,
          net_sales_quantity: 0,
          operating_net_profit_cny: BigDecimal("0")
        }
      }
    }

    with_stubbed_constructor(Ec::SkuPeriodProfitBreakdown, lambda { |**|
      Struct.new(:call).new(breakdown_payload)
    }) do
      result = Ec::SkuPeriodRoiQuery.new(
        sku_code: sku.sku_code,
        from_date: Date.new(2026, 6, 10),
        to_date: Date.new(2026, 6, 1),
        time_zone: ActiveSupport::TimeZone["Asia/Shanghai"]
      ).call

      assert_equal(-8, result[:days_count])
      assert_equal false, result[:calculable]
      assert_equal true, result[:invalid_date_range]
      assert_nil result.dig(:total, :average_daily_net_sales)
      assert_nil result.dig(:total, :projected_stock_qty_180d)
      assert_nil result.dig(:total, :average_inventory_qty)
      assert_nil result.dig(:total, :projected_months_to_clear)
      assert_nil result.dig(:total, :predicted_storage_cost_cny)
      assert_nil result.dig(:total, :predicted_interest_cost_cny)
      assert_nil result.dig(:total, :adjusted_operating_net_profit_cny)
      assert_nil result.dig(:total, :cost_base_cny)
      assert_nil result.dig(:total, :roi)
      assert_nil result.dig(:platforms, :wb, :average_daily_net_sales)
      assert_nil result.dig(:platforms, :wb, :projected_stock_qty_180d)
      assert_nil result.dig(:platforms, :wb, :average_inventory_qty)
      assert_nil result.dig(:platforms, :wb, :projected_months_to_clear)
      assert_nil result.dig(:platforms, :wb, :predicted_storage_cost_cny)
      assert_nil result.dig(:platforms, :wb, :predicted_interest_cost_cny)
      assert_nil result.dig(:platforms, :wb, :adjusted_operating_net_profit_cny)
      assert_nil result.dig(:platforms, :wb, :cost_base_cny)
      assert_nil result.dig(:platforms, :wb, :roi)
    end
  end

  test "returns nil roi and non calculable total when total net sales are non positive" do
    sku = Ec::Sku.create!(sku_code: @sku_code)
    Ec::SkuCost.create!(
      sku_code: sku.sku_code,
      purchase_price_cny: BigDecimal("20"),
      freight_to_by_cny: BigDecimal("5"),
      customs_misc_cny: BigDecimal("3"),
      customs_duty_rate: BigDecimal("0.1"),
      import_vat_rate: BigDecimal("0.2"),
      pkg_length_cm: BigDecimal("10"),
      pkg_width_cm: BigDecimal("20"),
      pkg_height_cm: BigDecimal("6")
    )

    breakdown_payload = {
      total: {
        sales_quantity: 4,
        return_quantity: 4,
        net_sales_quantity: 0,
        operating_net_profit_cny: BigDecimal("-80")
      },
      platforms: {
        wb: {
          sales_quantity: 5,
          return_quantity: 1,
          net_sales_quantity: 4,
          operating_net_profit_cny: BigDecimal("120")
        },
        ozon: {
          sales_quantity: 0,
          return_quantity: 2,
          net_sales_quantity: -2,
          operating_net_profit_cny: BigDecimal("-200")
        }
      }
    }

    with_stubbed_constructor(Ec::SkuPeriodProfitBreakdown, lambda { |**|
      Struct.new(:call).new(breakdown_payload)
    }) do
      result = Ec::SkuPeriodRoiQuery.new(
        sku_code: sku.sku_code,
        from_date: Date.new(2026, 6, 1),
        to_date: Date.new(2026, 6, 10),
        time_zone: ActiveSupport::TimeZone["Asia/Shanghai"]
      ).call

      assert_equal false, result[:missing_cost]
      assert_equal false, result[:invalid_date_range]
      assert_equal false, result[:calculable]

      assert_equal(
        {
          sales_quantity: 4,
          return_quantity: 4,
          net_sales_quantity: 0,
          average_daily_net_sales: nil,
          projected_stock_qty_180d: nil,
          average_inventory_qty: nil,
          projected_months_to_clear: nil,
          projected_unit_profit_cny: nil,
          projected_operating_net_profit_cny: nil,
          predicted_storage_cost_cny: nil,
          predicted_interest_cost_cny: nil,
          cost_base_cny: nil,
          operating_net_profit_cny: BigDecimal("-80"),
          adjusted_operating_net_profit_cny: nil,
          roi: nil
        },
        result[:total]
      )

      assert_equal(
        {
          sales_quantity: 5,
          return_quantity: 1,
          net_sales_quantity: 4,
          average_daily_net_sales: BigDecimal("0.4"),
          projected_stock_qty_180d: BigDecimal("72.0"),
          average_inventory_qty: BigDecimal("36.0"),
          projected_months_to_clear: BigDecimal("5.93863411415374463873309138898060046189376443418"),
          projected_unit_profit_cny: BigDecimal("30.0"),
          projected_operating_net_profit_cny: BigDecimal("2160.0"),
          predicted_storage_cost_cny: BigDecimal("25.6548993731441768393269548003961939953810623556576"),
          predicted_interest_cost_cny: BigDecimal("73.54404486967997360607060376113575612009237875288512"),
          cost_base_cny: BigDecimal("2476.8"),
          operating_net_profit_cny: BigDecimal("120"),
          adjusted_operating_net_profit_cny: BigDecimal("2060.80105575717584955460244143846804988452655889145728"),
          roi: BigDecimal("2060.80105575717584955460244143846804988452655889145728") / BigDecimal("2476.8")
        },
        result.dig(:platforms, :wb)
      )

      assert_equal(
        {
          sales_quantity: 0,
          return_quantity: 2,
          net_sales_quantity: -2,
          average_daily_net_sales: nil,
          projected_stock_qty_180d: nil,
          average_inventory_qty: nil,
          projected_months_to_clear: nil,
          projected_unit_profit_cny: nil,
          projected_operating_net_profit_cny: nil,
          predicted_storage_cost_cny: nil,
          predicted_interest_cost_cny: nil,
          cost_base_cny: nil,
          operating_net_profit_cny: BigDecimal("-200"),
          adjusted_operating_net_profit_cny: nil,
          roi: nil
        },
        result.dig(:platforms, :ozon)
      )
    end
  end

  test "treats zero goods cost as missing cost and non calculable" do
    sku = Ec::Sku.create!(sku_code: @sku_code)
    Ec::SkuCost.create!(
      sku_code: sku.sku_code,
      purchase_price_cny: BigDecimal("0"),
      freight_to_by_cny: BigDecimal("0"),
      customs_misc_cny: BigDecimal("0"),
      customs_duty_rate: BigDecimal("0"),
      import_vat_rate: BigDecimal("0"),
      pkg_length_cm: BigDecimal("10"),
      pkg_width_cm: BigDecimal("20"),
      pkg_height_cm: BigDecimal("6")
    )

    breakdown_payload = {
      total: {
        sales_quantity: 5,
        return_quantity: 1,
        net_sales_quantity: 4,
        operating_net_profit_cny: BigDecimal("120")
      },
      platforms: {
        wb: {
          sales_quantity: 5,
          return_quantity: 1,
          net_sales_quantity: 4,
          operating_net_profit_cny: BigDecimal("120")
        },
        ozon: {
          sales_quantity: 0,
          return_quantity: 0,
          net_sales_quantity: 0,
          operating_net_profit_cny: BigDecimal("0")
        }
      }
    }

    with_stubbed_constructor(Ec::SkuPeriodProfitBreakdown, lambda { |**|
      Struct.new(:call).new(breakdown_payload)
    }) do
      result = Ec::SkuPeriodRoiQuery.new(
        sku_code: sku.sku_code,
        from_date: Date.new(2026, 6, 1),
        to_date: Date.new(2026, 6, 10),
        time_zone: ActiveSupport::TimeZone["Asia/Shanghai"]
      ).call

      assert_equal BigDecimal("0.0"), result[:unit_goods_cost_cny]
      assert_equal true, result[:missing_cost]
      assert_equal false, result[:missing_volume]
      assert_equal false, result[:calculable]

      assert_equal(
        {
          sales_quantity: 5,
          return_quantity: 1,
          net_sales_quantity: 4,
          average_daily_net_sales: BigDecimal("0.4"),
          projected_stock_qty_180d: BigDecimal("72.0"),
          average_inventory_qty: BigDecimal("36.0"),
          projected_months_to_clear: BigDecimal("5.93863411415374463873309138898060046189376443418"),
          projected_unit_profit_cny: BigDecimal("30.0"),
          projected_operating_net_profit_cny: BigDecimal("2160.0"),
          predicted_storage_cost_cny: nil,
          predicted_interest_cost_cny: nil,
          cost_base_cny: nil,
          operating_net_profit_cny: BigDecimal("120"),
          adjusted_operating_net_profit_cny: nil,
          roi: nil
        },
        result[:total]
      )

      assert_equal(
        {
          sales_quantity: 5,
          return_quantity: 1,
          net_sales_quantity: 4,
          average_daily_net_sales: BigDecimal("0.4"),
          projected_stock_qty_180d: BigDecimal("72.0"),
          average_inventory_qty: BigDecimal("36.0"),
          projected_months_to_clear: BigDecimal("5.93863411415374463873309138898060046189376443418"),
          projected_unit_profit_cny: BigDecimal("30.0"),
          projected_operating_net_profit_cny: BigDecimal("2160.0"),
          predicted_storage_cost_cny: nil,
          predicted_interest_cost_cny: nil,
          cost_base_cny: nil,
          operating_net_profit_cny: BigDecimal("120"),
          adjusted_operating_net_profit_cny: nil,
          roi: nil
        },
        result.dig(:platforms, :wb)
      )
    end
  end

  test "treats missing package volume as non calculable" do
    sku = Ec::Sku.create!(sku_code: @sku_code)
    Ec::SkuCost.create!(
      sku_code: sku.sku_code,
      purchase_price_cny: BigDecimal("20"),
      freight_to_by_cny: BigDecimal("5"),
      customs_misc_cny: BigDecimal("3"),
      customs_duty_rate: BigDecimal("0.1"),
      import_vat_rate: BigDecimal("0.2"),
      pkg_length_cm: nil,
      pkg_width_cm: nil,
      pkg_height_cm: nil,
      pkg_volume_override_l: nil
    )

    breakdown_payload = {
      total: {
        sales_quantity: 5,
        return_quantity: 1,
        net_sales_quantity: 4,
        operating_net_profit_cny: BigDecimal("120")
      },
      platforms: {
        wb: {
          sales_quantity: 5,
          return_quantity: 1,
          net_sales_quantity: 4,
          operating_net_profit_cny: BigDecimal("120")
        },
        ozon: {
          sales_quantity: 0,
          return_quantity: 0,
          net_sales_quantity: 0,
          operating_net_profit_cny: BigDecimal("0")
        }
      }
    }

    with_stubbed_constructor(Ec::SkuPeriodProfitBreakdown, lambda { |**|
      Struct.new(:call).new(breakdown_payload)
    }) do
      result = Ec::SkuPeriodRoiQuery.new(
        sku_code: sku.sku_code,
        from_date: Date.new(2026, 6, 1),
        to_date: Date.new(2026, 6, 10),
        time_zone: ActiveSupport::TimeZone["Asia/Shanghai"]
      ).call

      assert_equal true, result[:missing_volume]
      assert_equal false, result[:calculable]
      assert_equal BigDecimal("0.0"), result[:unit_volume_l]
      assert_equal BigDecimal("72.0"), result.dig(:total, :projected_stock_qty_180d)
      assert_equal BigDecimal("36.0"), result.dig(:total, :average_inventory_qty)
      assert_equal BigDecimal("5.93863411415374463873309138898060046189376443418"), result.dig(:total, :projected_months_to_clear)
      assert_nil result.dig(:total, :predicted_storage_cost_cny)
      assert_nil result.dig(:total, :predicted_interest_cost_cny)
      assert_nil result.dig(:total, :adjusted_operating_net_profit_cny)
      assert_nil result.dig(:total, :roi)
    end
  end

  test "delegates projected roi calculation once per bucket with expected arguments" do
    sku = Ec::Sku.create!(sku_code: @sku_code)
    Ec::SkuCost.create!(
      sku_code: sku.sku_code,
      purchase_price_cny: BigDecimal("20"),
      freight_to_by_cny: BigDecimal("5"),
      customs_misc_cny: BigDecimal("3"),
      customs_duty_rate: BigDecimal("0.1"),
      import_vat_rate: BigDecimal("0.2"),
      pkg_length_cm: BigDecimal("10"),
      pkg_width_cm: BigDecimal("20"),
      pkg_height_cm: BigDecimal("6")
    )

    breakdown_payload = {
      total: {
        sales_quantity: 12,
        return_quantity: 2,
        net_sales_quantity: 10,
        operating_net_profit_cny: BigDecimal("500")
      },
      platforms: {
        wb: {
          sales_quantity: 9,
          return_quantity: 1,
          net_sales_quantity: 8,
          operating_net_profit_cny: BigDecimal("320")
        },
        ozon: {
          sales_quantity: 3,
          return_quantity: 1,
          net_sales_quantity: 2,
          operating_net_profit_cny: BigDecimal("180")
        }
      }
    }

    calculator_calls = []
    calculator_payload = {
      missing_cost: false,
      missing_volume: false,
      invalid_date_range: false,
      non_positive_net_sales: false,
      calculable: true,
      average_daily_net_sales: BigDecimal("1.0"),
      projected_stock_qty_180d: BigDecimal("180.0"),
      average_inventory_qty: BigDecimal("90.0"),
      projected_months_to_clear: BigDecimal("5.938022042467"),
      projected_unit_profit_cny: BigDecimal("50.0"),
      projected_operating_net_profit_cny: BigDecimal("9000.0"),
      predicted_storage_cost_cny: BigDecimal("6.41306372582644"),
      predicted_interest_cost_cny: BigDecimal("183.7206478060048"),
      cost_base_cny: BigDecimal("6192.0"),
      adjusted_operating_net_profit_cny: BigDecimal("309.86628846816876"),
      roi: BigDecimal("0.05004299942961124")
    }

    with_stubbed_constructor(Ec::SkuPeriodProfitBreakdown, lambda { |**|
      Struct.new(:call).new(breakdown_payload)
    }) do
      with_stubbed_singleton_method(Ec::ProjectedStockRoiCalculator, :call, lambda { |**kwargs|
        calculator_calls << kwargs
        calculator_payload
      }) do
        Ec::SkuPeriodRoiQuery.new(
          sku_code: sku.sku_code,
          from_date: Date.new(2026, 6, 1),
          to_date: Date.new(2026, 6, 10),
          time_zone: ActiveSupport::TimeZone["Asia/Shanghai"]
        ).call
      end
    end

    assert_equal(
      [
        {
          net_sales_quantity: 10,
          operating_profit_cny: BigDecimal("500"),
          days_count: 10,
          unit_goods_cost_cny: BigDecimal("34.4000"),
          unit_volume_l: BigDecimal("1.2000")
        },
        {
          net_sales_quantity: 8,
          operating_profit_cny: BigDecimal("320"),
          days_count: 10,
          unit_goods_cost_cny: BigDecimal("34.4000"),
          unit_volume_l: BigDecimal("1.2000")
        },
        {
          net_sales_quantity: 2,
          operating_profit_cny: BigDecimal("180"),
          days_count: 10,
          unit_goods_cost_cny: BigDecimal("34.4000"),
          unit_volume_l: BigDecimal("1.2000")
        }
      ],
      calculator_calls
    )
  end

  private

  def with_stubbed_constructor(klass, replacement)
    singleton_class = klass.singleton_class
    original_new = singleton_class.instance_method(:new)

    singleton_class.send(:define_method, :new, &replacement)
    yield
  ensure
    singleton_class.send(:define_method, :new, original_new)
  end

  def with_stubbed_singleton_method(klass, method_name, replacement)
    singleton_class = klass.singleton_class
    original_method = singleton_class.instance_method(method_name)

    singleton_class.send(:define_method, method_name, &replacement)
    yield
  ensure
    singleton_class.send(:define_method, method_name, original_method)
  end
end
