require "test_helper"

class Gbrain::OfficialDocumentImportTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  SOURCE_DIR = Rails.root.join("docs/官方文档-中文").freeze

  teardown do
    if defined?(GbrainPage) && GbrainPage.table_exists? && defined?(GbrainSourceDocument) && GbrainSourceDocument.table_exists?
      GbrainPage.where(source_document_id: GbrainSourceDocument.select(:id)).delete_all
    end
    GbrainSourceDocument.delete_all if defined?(GbrainSourceDocument) && GbrainSourceDocument.table_exists?
    GbrainImportBatch.delete_all if defined?(GbrainImportBatch) && GbrainImportBatch.table_exists?
  end

  test "dry run never creates a batch" do
    result = Gbrain::OfficialDocumentImport.call(
      directory: SOURCE_DIR, captured_on: "2026-10-13", platform: "wb", dry_run: true
    )

    assert_equal 361, result[:selected_documents]
    assert result[:dry_run]
    assert_equal 0, GbrainImportBatch.count
  end

  test "imports a limited platform slice idempotently without enqueueing classification" do
    first = Gbrain::OfficialDocumentImport.call(
      directory: SOURCE_DIR, captured_on: "2026-10-13", platform: "wb", limit: 2, enqueue: false
    )
    second = Gbrain::OfficialDocumentImport.call(
      directory: SOURCE_DIR, captured_on: "2026-10-13", platform: "wb", limit: 2, enqueue: false
    )

    assert_equal first[:selected_documents], second[:selected_documents]
    assert_equal 1, GbrainImportBatch.count
    assert_equal 2, GbrainSourceDocument.count
    assert_equal 2, GbrainSourceDocument.where(classification_status: "stored").count

    document = GbrainSourceDocument.first
    document.update_columns(classification_status: "classifying", classification_started_at: 1.hour.ago)
    Gbrain::OfficialDocumentImport.call(
      directory: SOURCE_DIR, captured_on: "2026-10-13", platform: "wb", limit: 2, enqueue: false
    )
    assert_equal "stored", document.reload.classification_status
  end

  test "classification job creates a deterministic collection page without calling the model" do
    Gbrain::OfficialDocumentImport.call(
      directory: SOURCE_DIR, captured_on: "2026-10-13", platform: "ozon", limit: 725, enqueue: false
    )
    document = GbrainSourceDocument.find_by!(document_kind: "directory")

    assert_enqueued_with(job: Gbrain::PageSyncJob) do
      Gbrain::OfficialDocumentClassificationJob.perform_now(document.id)
    end

    assert_equal "classified", document.reload.classification_status
    assert_equal "source", document.pages.first.page_type
    assert_equal document.target_slug, document.pages.first.slug
  end
end
