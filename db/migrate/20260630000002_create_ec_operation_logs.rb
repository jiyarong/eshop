class CreateEcOperationLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :ec_operation_logs do |t|
      t.references :user, foreign_key: { on_delete: :nullify }
      t.string :record_type, null: false
      t.bigint :record_id, null: false
      t.string :action, null: false
      t.jsonb :changeset, null: false, default: []
      t.datetime :created_at, null: false

      t.index [:record_type, :record_id]
      t.index :action
      t.index :created_at
    end
  end
end
