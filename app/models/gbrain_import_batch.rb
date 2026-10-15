class GbrainImportBatch < ApplicationRecord
  has_many :source_documents, class_name: "GbrainSourceDocument", foreign_key: :import_batch_id,
    inverse_of: :import_batch, dependent: :restrict_with_exception

  validates :platform, inclusion: { in: %w[ozon wb] }
  validates :captured_on, :manifest_sha256, presence: true
  validates :status, inclusion: { in: %w[importing imported failed] }
  validates :expected_documents, numericality: { only_integer: true, greater_than: 0 }

  def progress
    {
      id: id, platform: platform, captured_on: captured_on, status: status,
      expected_documents: expected_documents,
      classification: source_documents.group(:classification_status).count,
      writes: GbrainPage.where(source_document_id: source_documents.select(:id)).group(:sync_status).count
    }
  end
end
