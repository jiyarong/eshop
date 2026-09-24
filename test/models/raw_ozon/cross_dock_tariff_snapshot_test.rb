require "test_helper"
require "tmpdir"
require "zip"

class RawOzonCrossDockTariffSnapshotTest < ActiveSupport::TestCase
  def setup
    @xlsx_path = File.join(Dir.tmpdir, "ozon-cross-dock-#{SecureRandom.hex(8)}.xlsx")
    write_xlsx(@xlsx_path)
  end

  def teardown
    RawOzon::CrossDockTariff.delete_all
    RawOzon::CrossDockTariffSnapshot.delete_all
    File.delete(@xlsx_path) if File.exist?(@xlsx_path)
  end

  test "imports cross-dock per-liter tariffs into an effective dated snapshot" do
    snapshot = RawOzon::CrossDockTariffSnapshot.import_xlsx!(
      path: @xlsx_path,
      effective_from: Date.new(2026, 10, 30)
    )

    assert snapshot.succeeded?
    assert snapshot.is_current
    assert_equal Date.new(2026, 10, 30), snapshot.effective_from
    assert_equal 2, snapshot.row_count

    tariff = snapshot.cross_dock_tariffs.find_by(
      supply_receiving_zone_key: "АРХАНГЕЛЬСК",
      destination_cluster_key: "ВОРОНЕЖ"
    )
    assert_equal BigDecimal("9"), tariff.pallet_rub_per_l
    assert_equal BigDecimal("11.70"), tariff.box_rub_per_l
    assert_equal BigDecimal("23.40"), tariff.amount_for(volume_l: 2, package_type: :box)
    assert_equal snapshot.id, RawOzon::CrossDockTariffSnapshot.for_effective_date(Date.new(2026, 11, 1)).id
  end

  private

  def write_xlsx(path)
    workbook = <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        <sheets>
          <sheet name="Стоимость перевозки" sheetId="1" r:id="rId1"/>
        </sheets>
      </workbook>
    XML
    relationships = <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
      </Relationships>
    XML

    Zip::OutputStream.open(path) do |zip|
      zip.put_next_entry("xl/workbook.xml")
      zip.write(workbook)
      zip.put_next_entry("xl/_rels/workbook.xml.rels")
      zip.write(relationships)
      zip.put_next_entry("xl/worksheets/sheet1.xml")
      zip.write(sheet_xml([
        ["Тарифная зона приёма поставки", "Кластер получатель", "Палета", "Коробка"],
        ["Архангельск", "Воронеж", 9, 11.7],
        ["Алматы", "Самара", 20.1, 26.8]
      ]))
    end
  end

  def sheet_xml(rows)
    rows_xml = rows.each_with_index.map do |row, row_index|
      cells = row.each_with_index.map do |value, column_index|
        reference = "#{(65 + column_index).chr}#{row_index + 1}"
        if value.is_a?(String)
          "<c r=\"#{reference}\" t=\"inlineStr\"><is><t>#{value}</t></is></c>"
        else
          "<c r=\"#{reference}\"><v>#{value}</v></c>"
        end
      end.join
      "<row r=\"#{row_index + 1}\">#{cells}</row>"
    end.join

    "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetData>#{rows_xml}</sheetData></worksheet>"
  end
end
