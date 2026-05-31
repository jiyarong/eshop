class CreateEcOperationTasks < ActiveRecord::Migration[8.0]
  def change
    create_table :ec_operation_tasks do |t|
      t.string :task_type, null: false
      t.string :status, null: false, default: "open"
      t.string :priority, null: false, default: "medium"
      t.string :sku_code
      t.string :platform
      t.string :store_key
      t.string :title, null: false
      t.text :reason
      t.text :suggested_action
      t.string :owner_name
      t.date :due_on
      t.datetime :completed_at
      t.timestamps
    end

    add_index :ec_operation_tasks, :task_type
    add_index :ec_operation_tasks, :status
    add_index :ec_operation_tasks, :priority
    add_index :ec_operation_tasks, :sku_code
  end
end
