class CreateEcAttachmentsAndLinks < ActiveRecord::Migration[8.1]
  def change
    create_table :ec_attachments do |t|
      t.integer :attach_type, null: false
      t.string :oss_path, null: false
      t.string :qiniu_hash, null: false
      t.string :filename, null: false

      t.timestamps
    end

    add_index :ec_attachments, :attach_type
    add_index :ec_attachments, :oss_path, unique: true
    add_index :ec_attachments, :qiniu_hash

    create_table :ec_attachment_links do |t|
      t.references :attachable, polymorphic: true, null: false
      t.references :ec_attachment, null: false, foreign_key: { to_table: :ec_attachments }

      t.timestamps
    end

    add_index :ec_attachment_links,
              [:attachable_type, :attachable_id, :ec_attachment_id],
              unique: true,
              name: "idx_ec_attachment_links_unique_attachable"
  end
end
