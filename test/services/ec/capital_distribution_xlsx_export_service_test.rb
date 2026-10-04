require "test_helper"
require "zip"

class Ec::CapitalDistributionXlsxExportServiceTest < ActiveSupport::TestCase
  test "call exports summary sku and batch worksheets" do
    export = Ec::CapitalDistributionXlsxExportService.call(
      summary: {
        period_from: Date.new(2026, 1, 5),
        period_to: Date.new(2026, 1, 25),
        in_transit_goods_cost_cny: BigDecimal("123.45"),
        in_transit_quantity: 7,
        book_stock_goods_cost_cny: BigDecimal("234.56"),
        book_stock_quantity: 8,
        book_stock_customs_tax_cost_cny: BigDecimal("34.56"),
        total_amount_cny: BigDecimal("392.57"),
        total_quantity: 15,
        sales_revenue_cny: BigDecimal("888.88"),
        net_sales_quantity: 6,
        sold_goods_cost_cny: BigDecimal("66.66"),
        sold_customs_tax_cost_cny: BigDecimal("11.11"),
        net_profit_cny: BigDecimal("222.22"),
        unallocated_total_cny: BigDecimal("-9.99"),
        missing_cost_quantity: 2,
        missing_freight_quantity: 3,
        sku_count: 1,
        batch_count: 1
      },
      sku_rows: [{
        sku_code: "TEST-SKU",
        product_name: "测试商品",
        in_transit_goods_cost_cny: BigDecimal("123.45"),
        in_transit_quantity: 7,
        book_stock_goods_cost_cny: BigDecimal("234.56"),
        book_stock_quantity: 8,
        book_stock_customs_tax_cost_cny: BigDecimal("34.56"),
        net_sales_quantity: 6,
        sales_revenue_cny: BigDecimal("888.88"),
        sold_goods_cost_cny: BigDecimal("66.66"),
        sold_customs_tax_cost_cny: BigDecimal("11.11"),
        net_profit_cny: BigDecimal("222.22"),
        total_amount_cny: BigDecimal("392.57"),
        total_quantity: 15,
        batch_count: 1,
        missing_cost_quantity: 2,
        missing_freight_quantity: 3
      }],
      batch_rows: [{
        sku_code: "TEST-SKU",
        product_name: "测试商品",
        batch_code: "BATCH-001",
        batch_type: "normal",
        status: "received",
        cost_date: Date.new(2025, 12, 1),
        cost_effective_on: Date.new(2025, 11, 30),
        unit_goods_and_freight_cost_cny: BigDecimal("12.3456"),
        unit_customs_tax_cost_cny: BigDecimal("1.2345"),
        in_transit_quantity: 7,
        in_transit_goods_cost_cny: BigDecimal("123.45"),
        book_stock_quantity: 8,
        book_stock_goods_cost_cny: BigDecimal("234.56"),
        book_stock_customs_tax_cost_cny: BigDecimal("34.56"),
        sold_quantity: 6,
        missing_cost: false,
        missing_freight: true
      }],
      from_date: Date.new(2026, 1, 1),
      to_date: Date.new(2026, 1, 31),
      locale: :zh
    )

    assert_equal "capital-distribution-2026-01-01_to_2026-01-31.xlsx", export[:filename]
    assert_equal Ec::CapitalDistributionXlsxExportService::MIME_TYPE, export[:content_type]
    assert export[:data].bytesize.positive?

    workbook_xml, sheets = xlsx_xml(export[:data])
    workbook = Nokogiri::XML(workbook_xml)
    sheet_names = workbook.xpath("//*[local-name()='sheet']").map { |node| node["name"] }

    assert_equal ["数字汇总", "SKU汇总", "批次明细"], sheet_names
    assert_includes inline_strings(sheets.fetch("xl/worksheets/sheet1.xml")), "未分摊进 SKU 的金额"
    assert_includes numeric_values(sheets.fetch("xl/worksheets/sheet1.xml")), "9.99"
    assert_includes inline_strings(sheets.fetch("xl/worksheets/sheet2.xml")), "TEST-SKU"
    assert_includes inline_strings(sheets.fetch("xl/worksheets/sheet2.xml")), "已结算销售额"
    assert_includes numeric_values(sheets.fetch("xl/worksheets/sheet2.xml")), "888.88"
    assert_includes inline_strings(sheets.fetch("xl/worksheets/sheet3.xml")), "BATCH-001"
    assert_includes inline_strings(sheets.fetch("xl/worksheets/sheet3.xml")), "正常批次"
    assert_includes inline_strings(sheets.fetch("xl/worksheets/sheet3.xml")), "缺少运费"
    assert_includes inline_strings(sheets.fetch("xl/worksheets/sheet3.xml")), "是"
  end

  private

  def xlsx_xml(data)
    sheets = {}
    workbook_xml = nil

    Zip::File.open_buffer(StringIO.new(data)) do |zip|
      workbook_xml = zip.read("xl/workbook.xml")
      zip.glob("xl/worksheets/sheet*.xml").each { |entry| sheets[entry.name] = entry.get_input_stream.read }
    end

    [workbook_xml, sheets]
  end

  def inline_strings(xml)
    Nokogiri::XML(xml).xpath("//*[local-name()='c'][@t='inlineStr']//*[local-name()='t']").map(&:text)
  end

  def numeric_values(xml)
    Nokogiri::XML(xml).xpath("//*[local-name()='c']/*[local-name()='v']").map(&:text)
  end
end
