class GbrainSourceDocument < ApplicationRecord
  CLASSIFICATION_STATUSES = %w[stored classifying classified failed conflict].freeze

  belongs_to :import_batch, class_name: "GbrainImportBatch", inverse_of: :source_documents
  has_many :pages, class_name: "GbrainPage", foreign_key: :source_document_id, dependent: :nullify

  validates :platform, inclusion: { in: %w[ozon wb] }
  validates :relative_path, :source_key, :target_slug, :title, :raw_content,
    :raw_sha256, :classification_input_sha256, presence: true
  validates :document_kind, inclusion: { in: %w[article directory mixed collection_index] }
  validates :classification_status, inclusion: { in: CLASSIFICATION_STATUSES }
  validates :relative_path, uniqueness: { scope: :import_batch_id }

  attr_readonly :import_batch_id, :platform, :relative_path, :source_key, :source_url,
    :target_slug, :title, :document_kind, :raw_content, :raw_sha256,
    :source_metadata, :classification_input_sha256, :priority
end
