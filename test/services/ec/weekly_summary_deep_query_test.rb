require "test_helper"

class Ec::WeeklySummaryDeepQueryTest < ActiveSupport::TestCase
  RateStub = Struct.new(:rate_cny_rub, :rate_byn_rub)

  setup do
    @sku_codes = []
    create_sku_with_cost("WSUDEEP-A", purchase_price_cny: 8, freight_to_by_cny: 2, pkg_volume_override_l: 1.0)
    create_sku_with_cost("WSUDEEP-B", purchase_price_cny: nil, freight_to_by_cny: nil, pkg_volume_override_l: nil)
  end

  teardown do
    Ec::SkuCost.where(sku_code: @sku_codes).delete_all
    Ec::Sku.where(sku_code: @sku_codes).delete_all
  end

  test "run aggregates rows by sku for wsu deep payload" do
    query = Ec::WeeklySummaryDeepQuery.new(
      from_date: Date.new(2026, 5, 25),
      to_date: Date.new(2026, 5, 31),
      rate: RateStub.new(BigDecimal("7.2"), BigDecimal("0.28"))
    )

    query.define_singleton_method(:collect_rows) do |from_date, _to_date, _rate|
      rows = if from_date == Date.new(2026, 5, 25)
        [
          { sku: "WSUDEEP-A", platform: "WB", shop: "WB-1", net_sales: 5, revenue: 100, ads: 10, goods_cost: 30, pre_tax: 40, tax: 5, after_tax: 35 },
          { sku: "WSUDEEP-A", platform: "Ozon", shop: "OZ-1", net_sales: 3, revenue: 60, ads: 6, goods_cost: 18, pre_tax: 24, tax: 4, after_tax: 20 },
          { sku: "WSUDEEP-B", platform: "WB", shop: "WB-2", net_sales: 2, revenue: 20, ads: 2, goods_cost: 5, pre_tax: 8, tax: 1, after_tax: 7 }
        ]
      else
        [
          { sku: "WSUDEEP-A", platform: "WB", shop: "WB-9", net_sales: 4, revenue: 80, ads: 8, goods_cost: 24, pre_tax: 30, tax: 4, after_tax: 26 },
          { sku: "WSUDEEP-A", platform: "Ozon", shop: "OZ-9", net_sales: 2, revenue: 40, ads: 4, goods_cost: 12, pre_tax: 16, tax: 3, after_tax: 13 },
          { sku: "WSUDEEP-B", platform: "WB", shop: "WB-8", net_sales: 1, revenue: 10, ads: 1, goods_cost: 2, pre_tax: 3, tax: 1, after_tax: 2 }
        ]
      end
      [rows, { wb: -3.25, ozon: -1.75 }]
    end

    payload = query.run

    assert_equal "wsu_deep", payload[:report_type]
    assert_equal 57.0, payload.dig(:summary, :after_tax_with_unallocated)
    assert_equal "WSUDEEP-A", payload.dig(:rows, 0, :sku)
    assert_equal 8, payload.dig(:rows, 0, :net_sales)
    assert_in_delta 34.38, payload.dig(:rows, 0, :margin_pct).to_f, 0.1
    assert_in_delta 49.4, payload.dig(:rows, 0, :projected_roi_pct).to_f, 0.1
  end

  private

  def create_sku_with_cost(sku_code, purchase_price_cny:, freight_to_by_cny:, pkg_volume_override_l:)
    @sku_codes << sku_code
    Ec::Sku.create!(
      sku_code: sku_code,
      product_name: "Test #{sku_code}"
    )
    attributes = {
      sku_code: sku_code,
      customs_misc_cny: BigDecimal("0")
    }
    attributes[:purchase_price_cny] = BigDecimal(purchase_price_cny.to_s) unless purchase_price_cny.nil?
    attributes[:freight_to_by_cny] = BigDecimal(freight_to_by_cny.to_s) unless freight_to_by_cny.nil?
    attributes[:pkg_volume_override_l] = BigDecimal(pkg_volume_override_l.to_s) unless pkg_volume_override_l.nil?
    Ec::SkuCost.create!(attributes)
  end
end
