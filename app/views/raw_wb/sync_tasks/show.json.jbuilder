json.success true
json.data do
  json.sync_task do
      json.id @sync_task.id
      json.account_id @sync_task.account_id
      json.task_type @sync_task.task_type
      json.wb_task_id @sync_task.wb_task_id
      json.status @sync_task.status
      json.file_url @sync_task.file_url
      json.created_at @sync_task.created_at
      json.completed_at @sync_task.completed_at
  end
end
json.message @message || 'ok'
