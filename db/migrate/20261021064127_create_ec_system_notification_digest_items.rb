class CreateEcSystemNotificationDigestItems < ActiveRecord::Migration[8.1]
  def up
    create_table :ec_system_notification_digest_items do |t|
      t.references :digest, null: false, foreign_key: { to_table: :ec_system_notifications }
      t.references :notification, null: false, foreign_key: { to_table: :ec_system_notifications }
      t.timestamps

      t.index [ :digest_id, :notification_id ], unique: true, name: "idx_ec_notification_digest_items_unique"
    end

    Ec::SystemNotificationDailyDigest.backfill!
  end

  def down
    Ec::SystemNotification.where(notification_type: "daily_summary").destroy_all
    drop_table :ec_system_notification_digest_items
  end
end
