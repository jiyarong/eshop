require "test_helper"
require "zip"

class ImportSkuPrototypeImagesFromXlsxTest < ActiveSupport::TestCase
  SCRIPT_PATH = Rails.root.join("script/import_sku_prototype_images_from_xlsx.rb")

  setup do
    load SCRIPT_PATH
    @token = SecureRandom.hex(4).upcase
    @xlsx_path = Rails.root.join("tmp", "sku_prototype_images_#{@token}.xlsx")
    @sku = Ec::Sku.create!(sku_code: "IMAGE-SKU-#{@token}")
    write_workbook
  end

  teardown do
    Ec::Attachment.joins(:attachment_links).where(ec_attachment_links: { attachable: @sku }).find_each do |attachment|
      attachment.file.purge
      attachment.destroy!
    end
    Ec::OperationLog.where(record_type: "Ec::Attachment").delete_all
    @sku.destroy! if @sku
    File.delete(@xlsx_path) if File.exist?(@xlsx_path)
    Object.send(:remove_const, :SkuPrototypeImagesXlsxImport) if Object.const_defined?(:SkuPrototypeImagesXlsxImport)
  end

  test "dry run reports mapped images without creating attachments" do
    result = SkuPrototypeImagesXlsxImport.new(xlsx_path: @xlsx_path, env: {}, stdout: StringIO.new).call

    assert_equal 1, result.uploaded
    assert_equal 1, result.missing_sku
    assert_equal 0, Ec::Attachment.count
  end

  test "uploads each mapped image once and skips it on a subsequent run" do
    importer = SkuPrototypeImagesXlsxImport.new(xlsx_path: @xlsx_path, env: { "APPLY" => "1" }, stdout: StringIO.new)

    assert_difference "Ec::Attachment.count", 1 do
      result = importer.call
      assert_equal 1, result.uploaded
      assert_equal 1, result.missing_sku
    end

    attachment = @sku.attachments.sole
    assert attachment.prototype_media?
    assert attachment.file.attached?
    assert_equal "image/png", attachment.file.content_type
    assert_equal "#{@sku.sku_code}-prototype.png", attachment.filename

    assert_no_difference "Ec::Attachment.count" do
      result = importer.call
      assert_equal 1, result.already_uploaded
    end
  end

  private

  def write_workbook
    Zip::OutputStream.open(@xlsx_path) do |zip|
      zip.put_next_entry("xl/sharedStrings.xml")
      zip.write <<~XML
        <sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><si><t>#{@sku.sku_code}</t></si><si><t>MISSING-#{@token}</t></si></sst>
      XML
      zip.put_next_entry("xl/worksheets/sheet1.xml")
      zip.write <<~XML
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheetData><row r="2"><c r="A2" t="s"><v>0</v></c></row><row r="3"><c r="A3" t="s"><v>1</v></c></row></sheetData><drawing r:id="rId1"/></worksheet>
      XML
      zip.put_next_entry("xl/worksheets/_rels/sheet1.xml.rels")
      zip.write <<~XML
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/drawing" Target="../drawings/drawing1.xml"/></Relationships>
      XML
      zip.put_next_entry("xl/drawings/drawing1.xml")
      zip.write <<~XML
        <xdr:wsDr xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><xdr:oneCellAnchor><xdr:from><xdr:col>1</xdr:col><xdr:row>1</xdr:row></xdr:from><xdr:pic><xdr:blipFill><a:blip r:embed="rId1"/></xdr:blipFill></xdr:pic></xdr:oneCellAnchor><xdr:oneCellAnchor><xdr:from><xdr:col>1</xdr:col><xdr:row>2</xdr:row></xdr:from><xdr:pic><xdr:blipFill><a:blip r:embed="rId2"/></xdr:blipFill></xdr:pic></xdr:oneCellAnchor></xdr:wsDr>
      XML
      zip.put_next_entry("xl/drawings/_rels/drawing1.xml.rels")
      zip.write <<~XML
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/image1.png"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/image2.png"/></Relationships>
      XML
      zip.put_next_entry("xl/media/image1.png")
      zip.write "png image one"
      zip.put_next_entry("xl/media/image2.png")
      zip.write "png image two"
    end
  end
end
