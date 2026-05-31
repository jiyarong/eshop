json.success true
json.data do
  json.analytics_search_term do
      json.id @analytics_search_term.id
      json.account_id @analytics_search_term.account_id
      json.stat_date @analytics_search_term.stat_date
      json.keyword @analytics_search_term.keyword
      json.nm_id @analytics_search_term.nm_id
      json.orders @analytics_search_term.orders
      json.avg_position @analytics_search_term.avg_position
      json.frequency @analytics_search_term.frequency
  end
end
json.message @message || 'ok'
