require "test_helper"

class AttachmentsHelperTest < ActionView::TestCase
  test "maps common file extensions to icon kinds" do
    assert_equal :image, attachment_file_kind("photo.webp")
    assert_equal :pdf, attachment_file_kind("manual.pdf")
    assert_equal :spreadsheet, attachment_file_kind("report.xlsx")
    assert_equal :document, attachment_file_kind("contract.docx")
    assert_equal :archive, attachment_file_kind("source.zip")
    assert_equal :unknown, attachment_file_kind("data.bin")
  end

  test "only offers Office preview when the file has an externally reachable storage URL" do
    qiniu_file = Struct.new(:service).new(ActiveStorage::Service::QiniuService.allocate)
    disk_file = Struct.new(:service).new(Object.new)

    assert attachment_office_previewable?(Struct.new(:filename, :file).new("report.xlsx", qiniu_file))
    assert_not attachment_office_previewable?(Struct.new(:filename, :file).new("report.xlsx", disk_file))
  end

  test "uses safe content types for browser previews" do
    text_attachment = Struct.new(:filename).new("notes.txt")
    archive_attachment = Struct.new(:filename).new("files.zip")

    assert attachment_browser_previewable?(text_attachment)
    assert_equal "text/plain", attachment_browser_preview_content_type(text_attachment)
    assert_not attachment_browser_previewable?(archive_attachment)
  end
end
