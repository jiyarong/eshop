require "test_helper"
require "zip"

class WeeklyProfitReports::XlsxExportServiceTest < ActiveSupport::TestCase
  test "call returns xlsx binary and filename" do
    report = {
      report_type: "wsu",
      period: { from_date: "2026-05-18", to_date: "2026-05-24" }
    }
    layout = {
      sheet_name: "WSU:W21",
      column_widths: [20, 20],
      sections: [
        {
          rows: [["H1", "H2"], ["A", 1.5]],
          row_types: [:header, :data]
        }
      ]
    }

    builder_class = WeeklyProfitReports::ExportLayoutBuilder
    original_build = builder_class.method(:build)
    captured_report = nil
    builder_class.define_singleton_method(:build) do |report:|
      captured_report = report
      layout
    end

    export = WeeklyProfitReports::XlsxExportService.call(report: report)

    assert_equal report.deep_symbolize_keys, captured_report
    assert_equal "weekly-profit-wsu-w21-2026-05-18_to_2026-05-24.xlsx", export[:filename]
    assert export[:data].bytesize.positive?

    entries = []
    Zip::File.open_buffer(StringIO.new(export[:data])) do |zip|
      entries = zip.entries.map(&:name)
    end

    assert_includes entries, "[Content_Types].xml"
    assert_includes entries, "xl/workbook.xml"
    assert_includes entries, "xl/worksheets/sheet1.xml"
  ensure
    builder_class.define_singleton_method(:build, original_build)
  end

  test "call converts google sheet pixel widths to reasonable excel widths" do
    report = {
      report_type: "wsu",
      period: { from_date: "2026-05-18", to_date: "2026-05-24" }
    }
    layout = {
      sheet_name: "WSU:W21",
      column_widths: [140, 70],
      sections: [
        {
          rows: [["H1", "H2"], ["A", 1.5]],
          row_types: [:header, :data]
        }
      ]
    }

    builder_class = WeeklyProfitReports::ExportLayoutBuilder
    original_build = builder_class.method(:build)
    builder_class.define_singleton_method(:build) { |report:| layout }

    export = WeeklyProfitReports::XlsxExportService.call(report: report)
    sheet_xml = nil

    Zip::File.open_buffer(StringIO.new(export[:data])) do |zip|
      sheet_xml = zip.read("xl/worksheets/sheet1.xml")
    end

    widths = sheet_xml.scan(/<col[^>]*width="([^"]+)"/).flatten.map(&:to_f)

    assert_operator widths[0], :<, 30.0
    assert_operator widths[1], :<, 15.0
  ensure
    builder_class.define_singleton_method(:build, original_build)
  end
end
