class CreateGbrainPages < ActiveRecord::Migration[8.1]
  def change
    create_table :gbrain_pages do |t|
      t.string :slug, null: false
      t.text :content, null: false
      t.string :sync_status, null: false, default: "pending"
      t.datetime :content_updated_at, null: false
      t.datetime :knowledge_base_written_at
      t.datetime :delete_requested_at
      t.text :last_error

      t.timestamps
    end

    add_index :gbrain_pages, :slug, unique: true
    add_index :gbrain_pages, :sync_status
  end
end
