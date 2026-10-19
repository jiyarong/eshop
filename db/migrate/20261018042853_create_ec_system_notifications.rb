class CreateEcSystemNotifications < ActiveRecord::Migration[8.1]
  def change
    create_table :ec_system_notifications do |t|
      t.string :notification_type, null: false
      t.string :severity, null: false, default: "warning"
      t.string :title, null: false
      t.text :body, null: false
      t.string :sku_code
      t.bigint :store_id
      t.string :source_type
      t.bigint :source_id
      t.string :fingerprint
      t.jsonb :metadata, null: false, default: {}
      t.string :target_path, null: false
      t.datetime :occurred_at, null: false
      t.datetime :resolved_at
      t.datetime :last_seen_at, null: false
      t.integer :occurrence_count, null: false, default: 1
      t.timestamps

      t.index [:notification_type, :occurred_at], name: "idx_ec_system_notifications_type_time"
      t.index [:sku_code, :occurred_at], name: "idx_ec_system_notifications_sku_time"
      t.index [:source_type, :source_id], name: "idx_ec_system_notifications_source"
      t.index :fingerprint, unique: true, where: "fingerprint IS NOT NULL AND resolved_at IS NULL",
        name: "idx_ec_system_notifications_active_fingerprint"
      t.index :store_id
    end

    create_table :ec_system_notification_recipients do |t|
      t.references :notification, null: false, foreign_key: { to_table: :ec_system_notifications }
      t.references :user, null: false, foreign_key: true
      t.datetime :read_at
      t.datetime :deleted_at
      t.timestamps

      t.index [:notification_id, :user_id], unique: true, name: "idx_ec_system_notification_recipients_unique"
      t.index [:user_id, :deleted_at, :read_at], name: "idx_ec_system_notification_recipients_inbox"
    end
  end
end
