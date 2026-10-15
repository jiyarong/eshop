class CreateGbrainSourceImports < ActiveRecord::Migration[8.1]
  def change
    create_table :gbrain_import_batches do |t|
      t.string :platform, null: false
      t.date :captured_on, null: false
      t.string :manifest_sha256, null: false
      t.text :raw_manifest
      t.string :status, null: false, default: "importing"
      t.integer :expected_documents, null: false
      t.text :last_error
      t.timestamps
    end
    add_index :gbrain_import_batches, [:platform, :captured_on, :manifest_sha256],
      unique: true, name: "index_gbrain_batches_on_source_snapshot"

    create_table :gbrain_source_documents do |t|
      t.references :import_batch, null: false, foreign_key: { to_table: :gbrain_import_batches }
      t.string :platform, null: false
      t.string :relative_path, null: false
      t.string :source_key, null: false
      t.string :source_url
      t.string :target_slug, null: false
      t.string :title, null: false
      t.string :document_kind, null: false
      t.text :raw_content, null: false
      t.string :raw_sha256, null: false
      t.jsonb :source_metadata, null: false, default: {}
      t.string :classification_input_sha256, null: false
      t.string :classification_status, null: false, default: "stored"
      t.jsonb :classification, null: false, default: {}
      t.datetime :classification_started_at
      t.datetime :classified_at
      t.integer :classification_attempts, null: false, default: 0
      t.integer :priority, null: false, default: 0
      t.text :last_error
      t.timestamps
    end
    add_index :gbrain_source_documents, [:import_batch_id, :relative_path],
      unique: true, name: "index_gbrain_documents_on_batch_path"
    add_index :gbrain_source_documents, [:platform, :source_key, :classification_input_sha256],
      name: "index_gbrain_documents_on_classification_input"
    add_index :gbrain_source_documents, [:import_batch_id, :classification_status],
      name: "index_gbrain_documents_on_batch_status"

    add_reference :gbrain_pages, :source_document, foreign_key: { to_table: :gbrain_source_documents }
    add_column :gbrain_pages, :imported_payload_sha256, :string
    add_column :gbrain_pages, :synced_payload_sha256, :string
  end
end
