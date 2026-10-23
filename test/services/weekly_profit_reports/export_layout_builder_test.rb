require "test_helper"

class WeeklyProfitReports::ExportLayoutBuilderTest < ActiveSupport::TestCase
  test "SKU aggregate export hides warehouse costs even when supplied in the payload" do
    report = {
      report_type: "wsu_deep", period: { from_date: "2026-06-01", to_date: "2026-06-07" },
      summary: { total_after_tax: 100, total_own_warehouse_cost: 25, total_after_own_warehouse_cost: 75 },
      rows: [{ sku: "OWN-COST", net_sales: 1, revenue: 200, after_tax: 100, own_warehouse_cost: 25, after_own_warehouse_cost: 75 }]
    }
    layout = WeeklyProfitReports::ExportLayoutBuilder.build(report: report)
    section = layout[:sections].first
    assert_equal GoogleSheets::WeeklySummaryDeepService::HDR_ZH.size + 2, section[:rows][0].size
    assert_equal section[:rows][0].size, layout[:column_widths].size
    %i[own_warehouse_cost after_own_warehouse_cost].each do |key|
      assert_not_includes section[:rows][0], I18n.t("weekly_profit_reports.columns.wsu_deep.#{key}", locale: :zh)
    end
    summary_labels = layout[:sections].last[:rows].map(&:first).join("|")
    %i[total_own_warehouse_cost total_after_own_warehouse_cost].each do |key|
      assert_not_includes summary_labels, I18n.t("weekly_profit_reports.summary.wsu_deep.#{key}", locale: :zh)
    end
    assert_equal [nil, nil], section[:rows][2].last(2)
  end

  test "SKU aggregate export carries the unconfirmed-country units and sales at the end, empty when none" do
    report = {
      report_type: "wsu_deep", period: { from_date: "2026-06-01", to_date: "2026-06-07" },
      summary: { total_after_tax: 130, total_dest_pending_count: 2, total_dest_pending_sale: 35.5, total_own_warehouse_cost: 5, total_after_own_warehouse_cost: 125 },
      rows: [
        { sku: "PENDING-A", net_sales: 1, revenue: 200, after_tax: 100, dest_pending_count: 2, dest_pending_sale: 35.5, own_warehouse_cost: 5, after_own_warehouse_cost: 95 },
        { sku: "CLEAN-B", net_sales: 1, revenue: 100, after_tax: 30, dest_pending_count: 0, dest_pending_sale: 0.0, own_warehouse_cost: 0, after_own_warehouse_cost: 30 }
      ]
    }
    section = WeeklyProfitReports::ExportLayoutBuilder.build(report: report)[:sections].first

    assert_equal [2, 35.5], section[:rows][2].last(2)
    assert_equal [nil, nil], section[:rows][3].last(2)
    assert_equal [2, 35.5], section[:rows].last.last(2)
    assert_equal I18n.t("weekly_profit_reports.columns.wsu_deep.dest_pending_count", locale: :zh), section[:rows][0][-2]
    assert_equal I18n.t("weekly_profit_reports.columns.wsu_deep.dest_pending_sale", locale: :ru), section[:rows][1][-1]
    summary_labels = WeeklyProfitReports::ExportLayoutBuilder.build(report: report)[:sections].last[:rows].map(&:first).join("|")
    assert_includes summary_labels, I18n.t("weekly_profit_reports.summary.wsu_deep.total_dest_pending_sale", locale: :zh)
  end

  test "build returns wsu layout with google sheet headers and summary block" do
    report = {
      report_type: "wsu",
      period: { from_date: "2026-05-25", to_date: "2026-05-31" },
      comparison: {
        rows: {
          "SKU-A|WB|WB-1" => {
            net_sales: { previous: 3, delta_pct: 33.33 },
            revenue: { previous: 90.0, delta_pct: 11.11 }
          }
        }
      },
      summary: {
        period_label: "2026-05-25 ~ 2026-05-31",
        rate_cny_rub: BigDecimal("10.1"),
        rate_byn_rub: BigDecimal("3.2"),
        wb_sales_revenue: 101.0,
        wb_ads: 11.0,
        wb_goods_cost: 21.0,
        wb_pre_tax: 31.0,
        wb_after_tax: 26.0,
        ozon_sales_revenue: 0.0,
        ozon_ads: 0.0,
        ozon_goods_cost: 0.0,
        ozon_pre_tax: 0.0,
        ozon_after_tax: 0.0,
        total_sales_revenue: 101.0,
        total_after_tax: 26.0,
        total_margin_pct: 25.74,
        wb_unallocated: -2.0,
        ozon_unallocated: 0.0,
        unallocated_total: -2.0,
        after_tax_with_unallocated: 24.0,
        margin_with_unallocated_pct: 23.76
      },
      rows: [
        { sku: "SKU-A", platform: "WB", shop: "WB-1", net_sales: 4, revenue: 100.0, ads: 10.0, goods_cost: 20.0, pre_tax: 30.0, tax: 4.0, after_tax: 26.0, margin_pct: 26.0 }
      ]
    }

    layout = WeeklyProfitReports::ExportLayoutBuilder.build(report: report)

    assert_equal "WSU:W22", layout[:sheet_name]
    assert_equal GoogleSheets::WeeklySummaryService::HDR_ZH, layout[:sections][0][:rows][0]
    assert_equal GoogleSheets::WeeklySummaryService::HDR_RU, layout[:sections][0][:rows][1]
    assert_equal "合计 / Итого", layout[:sections][0][:rows].last[0]
    assert_equal "项目", layout[:sections][1][:rows][0][0]
    assert_includes layout[:sections][1][:rows].flatten, "总销售额"
    assert_includes layout[:sections][1][:rows].flatten, 101.0
  end

  test "build returns wb wr layout with sku section and summary section" do
    report = {
      report_type: "wr",
      period: { from_date: "2026-05-25", to_date: "2026-05-31" },
      meta: {
        platform: "wb",
        account: { name: "WB Test Shop" },
        rates: { rate_cny_rub: 10.1, rate_byn_rub: 3.2 }
      },
      summary: { tax_regime: "usn" },
      rows: [
        {
          nm_id: 123,
          vendor_code: "SKU-WB",
          region: "Moscow",
          sales_qty: 5,
          return_qty: 1,
          net_qty: 4,
          retail_amount: 140.0,
          settlement: 100.0,
          acquiring: 5.0,
          delivery: 8.0,
          reimb: 1.0,
          logistics_reimb: 2.0,
          pickup: 1.0,
          penalty: 0.0,
          storage: 3.0,
          ad: 4.0,
          net: 76.0,
          tax_base: 80.0,
          import_vat: 2.0,
          goods_cost: 20.0,
          pre_tax: 56.0,
          tax: 6.0,
          after_tax: 50.0
        }
      ],
      extras: {
        unallocated: {
          "未归属费用" => 7.5
        }
      }
    }

    layout = WeeklyProfitReports::ExportLayoutBuilder.build(report: report)

    assert_equal "WR:W22-WB Test Shop", layout[:sheet_name]
    assert_equal GoogleSheets::WbWeeklyReportService::SKU_HDR_ZH, layout[:sections][0][:rows][0]
    assert_equal GoogleSheets::WbWeeklyReportService::SKU_HDR_RU, layout[:sections][0][:rows][1]
    assert_equal "合计 / Итого", layout[:sections][0][:rows].last[1]
    assert_equal "项目 / Статья", layout[:sections][1][:rows][0][0]
    assert_includes layout[:sections][1][:rows].flatten, "未归属费用"
    assert_includes layout[:sections][1][:rows].flatten, "税后净利(SKU) / Чистая прибыль (SKU)"
  end

  test "build returns ozon wr layout with ad and destination sections" do
    report = {
      report_type: "wr",
      period: { from_date: "2026-05-25", to_date: "2026-05-31" },
      meta: {
        platform: "ozon",
        account: { name: "Ozon Test Shop" },
        rates: { rate_cny_rub: 10.1 }
      },
      rows: [
        {
          ozon_sku_id: "OZ-1",
          sku_code: "SKU-OZ",
          sales_revenue: 100.0,
          commission: 12.0,
          delivery_charge: 6.0,
          payment_fee: 1.0,
          dispatch_fee: 2.0,
          packing_fee: 1.5,
          return_delivery: 0.5,
          storage_fee: 0.3,
          defect_fee: 0.0,
          crossdock_fee: 0.2,
          order_count: 6,
          net_sales_count: 5,
          return_count: 1,
          total_ad_cost: 8.0,
          promotion_cost: -3.0,
          ppc_cost: -5.0,
          book_profit: 55.0,
          book_profit_after_ad: 47.0,
          blr_count: 2,
          export_count: 1,
          goods_cost: 20.0,
          blr_tax: 3.0,
          export_refund: 1.0,
          pre_tax_profit: 24.0,
          after_tax_profit: 22.0
        }
      ],
      extras: {
        unallocated: {
          total: 4.0,
          rows: [
            { type_id: 96, amount: 1.5 },
            { type_id: 94, amount: 2.5 }
          ]
        }
      }
    }

    layout = WeeklyProfitReports::ExportLayoutBuilder.build(report: report)

    assert_equal "WR:W22-Ozon Test Shop", layout[:sheet_name]
    assert_equal GoogleSheets::OzonWeeklyReportService::SKU_HDR_ZH, layout[:sections][0][:rows][0]
    assert_equal GoogleSheets::OzonWeeklyReportService::AD_HDR_ZH, layout[:sections][2][:rows][0]
    assert_equal GoogleSheets::OzonWeeklyReportService::DST_HDR_ZH, layout[:sections][3][:rows][0]
    assert_includes layout[:sections][1][:rows].flatten, "广告费合计 / Реклама итого"
    assert_includes layout[:sections][2][:rows].flatten, "合计 / Итого"
    assert_includes layout[:sections][3][:rows].flatten, 2
  end
end
