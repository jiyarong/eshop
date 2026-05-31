json.success true
json.data do
  json.sync_tasks do
    json.array! @sync_tasks do |sync_task|
      json.id sync_task.id
      json.task_type sync_task.task_type
      json.wb_task_id sync_task.wb_task_id
      json.status sync_task.status
      json.created_at sync_task.created_at
      json.completed_at sync_task.completed_at
    end
  end
  json.meta do
    json.current_page @sync_tasks.current_page
    json.total_pages @sync_tasks.total_pages
    json.total_count @sync_tasks.total_count
  end
end
json.message @message || 'ok'