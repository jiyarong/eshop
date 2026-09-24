require "test_helper"
require "tmpdir"
require "zip"

class RawOzonLogisticsTariffSnapshotTest < ActiveSupport::TestCase
  def setup
    @xlsx_path = File.join(Dir.tmpdir, "ozon-logistics-#{SecureRandom.hex(8)}.xlsx")
    write_xlsx(@xlsx_path)
  end

  def teardown
    RawOzon::LogisticsTariff.delete_all
    RawOzon::DefaultLogisticsTariff.delete_all
    RawOzon::LogisticsTariffSnapshot.delete_all
    File.delete(@xlsx_path) if File.exist?(@xlsx_path)
  end

  test "imports route and default sheets into an effective dated current snapshot" do
    snapshot = RawOzon::LogisticsTariffSnapshot.import_xlsx!(
      path: @xlsx_path,
      effective_from: Date.new(2026, 10, 1)
    )

    assert snapshot.succeeded?
    assert snapshot.is_current
    assert_equal Date.new(2026, 10, 1), snapshot.effective_from
    assert_equal 2, snapshot.route_row_count
    assert_equal 2, snapshot.default_row_count

    route = snapshot.logistics_tariffs.order(:volume_band_order).first
    assert_equal "ВОРОНЕЖ", route.origin_cluster_key
    assert_equal BigDecimal("40"), route.fbo_rub
    assert_equal BigDecimal("0.2"), route.volume_max_l
    assert_equal 1, RawOzon::LogisticsTariff.for_volume(BigDecimal("0.1")).count
    assert_equal 1, RawOzon::DefaultLogisticsTariff.for_volume(BigDecimal("900")).count
    assert_equal snapshot.id, RawOzon::LogisticsTariffSnapshot.for_effective_date(Date.new(2026, 10, 2)).id
  end

  test "reimporting the same file returns the existing successful snapshot" do
    first = RawOzon::LogisticsTariffSnapshot.import_xlsx!(
      path: @xlsx_path,
      effective_from: Date.new(2026, 10, 1)
    )
    second = RawOzon::LogisticsTariffSnapshot.import_xlsx!(
      path: @xlsx_path,
      effective_from: Date.new(2026, 10, 1)
    )

    assert_equal first.id, second.id
    assert_equal 1, RawOzon::LogisticsTariffSnapshot.count
  end

  private

  def write_xlsx(path)
    workbook = <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        <sheets>
          <sheet name="Логистика РФ" sheetId="1" r:id="rId1"/>
          <sheet name="Тарифы по умолчанию" sheetId="2" r:id="rId2"/>
        </sheets>
      </workbook>
    XML
    relationships = <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
        <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/>
      </Relationships>
    XML

    Zip::OutputStream.open(path) do |zip|
      zip.put_next_entry("xl/workbook.xml")
      zip.write(workbook)
      zip.put_next_entry("xl/_rels/workbook.xml.rels")
      zip.write(relationships)
      zip.put_next_entry("xl/worksheets/sheet1.xml")
      zip.write(sheet_xml([
        [nil, "0-0,200 л", "Воронеж", "Воронеж", 40, 11, 40, 11, 40],
        [nil, "От 800,001 л", "Воронеж", "Москва", 100, 90, 100, 90, 100]
      ]))
      zip.put_next_entry("xl/worksheets/sheet2.xml")
      zip.write(sheet_xml([
        [nil, "0-0,200 л", 35, 11, 35, 11, 35],
        [nil, "От 800,001 л", 100, 90, 100, 90, 100]
      ]))
    end
  end

  def sheet_xml(rows)
    rows_xml = rows.each_with_index.map do |row, row_index|
      cells = row.each_with_index.filter_map do |value, column_index|
        next if value.nil?

        reference = "#{(65 + column_index).chr}#{row_index + 4}"
        if value.is_a?(String)
          "<c r=\"#{reference}\" t=\"inlineStr\"><is><t>#{value}</t></is></c>"
        else
          "<c r=\"#{reference}\"><v>#{value}</v></c>"
        end
      end.join
      "<row r=\"#{row_index + 4}\">#{cells}</row>"
    end.join

    "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetData>#{rows_xml}</sheetData></worksheet>"
  end
end
