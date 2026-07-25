class CreateEcSnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :ec_snapshots do |t|
      t.date :snapshot_date, null: false
      t.string :snapshot_type, null: false
      t.jsonb :content, null: false, default: {}

      t.index [ :snapshot_type, :snapshot_date ], unique: true
    end
  end
end
