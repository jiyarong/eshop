class AddResultsToRawWbSyncTasks < ActiveRecord::Migration[8.1]
  def change
    add_column :raw_wb_sync_tasks, :results, :jsonb, default: {}, null: false
  end
end
