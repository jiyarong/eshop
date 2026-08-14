json.success true
json.data do
  json.analytics_search_terms do
    json.array! @analytics_search_terms do |analytics_search_term|
      json.id analytics_search_term.id
      json.period_from analytics_search_term.period_from
      json.period_to analytics_search_term.period_to
      json.keyword analytics_search_term.keyword
      json.nm_id analytics_search_term.nm_id
      json.orders analytics_search_term.orders
      json.avg_position analytics_search_term.avg_position
      json.frequency analytics_search_term.frequency
      json.currency analytics_search_term.currency
      json.synced_at analytics_search_term.synced_at
      json.raw_json analytics_search_term.raw_json
    end
  end
  json.meta do
    json.current_page @analytics_search_terms.current_page
    json.total_pages @analytics_search_terms.total_pages
    json.total_count @analytics_search_terms.total_count
  end
end
json.message @message || 'ok'
