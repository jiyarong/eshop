require "test_helper"

class Gbrain::OfficialDocumentCatalogTest < ActiveSupport::TestCase
  SOURCE_DIR = Rails.root.join("docs/官方文档-中文").freeze

  test "scans both official collections and classifies directory pages without dropping mixed content" do
    catalog = Gbrain::OfficialDocumentCatalog.new(directory: SOURCE_DIR)

    assert_equal 1_086, catalog.entries.size
    assert_equal({ "ozon" => 725, "wb" => 361 }, catalog.report[:platforms])
    assert_equal({ "collection_index" => 2, "article" => 946, "directory" => 134, "mixed" => 4 }, catalog.report[:kinds])
    assert_equal 1_086, catalog.entries.map { |entry| entry[:target_slug] }.uniq.size
    assert catalog.entries.all? { |entry| entry[:classification_input_sha256].match?(/\A[0-9a-f]{64}\z/) }
  end

  test "keeps source bytes and detects the WB manifest snapshot" do
    catalog = Gbrain::OfficialDocumentCatalog.new(directory: SOURCE_DIR, platform: "wb")
    entry = catalog.entries.find { |candidate| candidate[:relative_path].end_with?("005_sales-funnel-report.md") }

    assert_equal "wb", entry[:platform]
    assert_equal "analytics", entry[:source_metadata]["front_matter"].fetch("category")
    assert_equal entry[:bytes], catalog.read(entry).bytesize
    assert_match(/2026-10-13T19:45:58/, catalog.manifests.fetch("wb"))
  end

  test "rejects a platform outside the supported official collections" do
    error = assert_raises(Gbrain::OfficialDocumentCatalog::InvalidSource) do
      Gbrain::OfficialDocumentCatalog.new(directory: SOURCE_DIR, platform: "other")
    end

    assert_includes error.message, "Unknown platform"
  end
end
