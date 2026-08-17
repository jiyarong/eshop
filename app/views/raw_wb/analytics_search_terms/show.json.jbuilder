json.success true
json.data do
  json.analytics_search_term do
      json.id @analytics_search_term.id
      json.account_id @analytics_search_term.account_id
      json.period_from @analytics_search_term.period_from
      json.period_to @analytics_search_term.period_to
      json.keyword @analytics_search_term.keyword
      json.nm_id @analytics_search_term.nm_id
      json.orders @analytics_search_term.orders
      json.avg_position @analytics_search_term.avg_position
      json.frequency @analytics_search_term.frequency
      json.currency @analytics_search_term.currency
      json.synced_at @analytics_search_term.synced_at
      json.raw_json @analytics_search_term.raw_json
  end
end
json.message @message || 'ok'
