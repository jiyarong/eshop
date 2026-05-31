json.success false
json.data do
  json.errors @errors || []
end
json.message @message || 'Validation failed'
