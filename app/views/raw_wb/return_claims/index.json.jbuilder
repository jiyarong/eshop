json.success true
json.data do
  json.return_claims do
    json.array! @return_claims do |return_claim|
      json.id return_claim.id
      json.wb_claim_id return_claim.wb_claim_id
      json.order_id return_claim.order_id
      json.nm_id return_claim.nm_id
      json.status return_claim.status
      json.wb_created_at return_claim.wb_created_at
    end
  end
  json.meta do
    json.current_page @return_claims.current_page
    json.total_pages @return_claims.total_pages
    json.total_count @return_claims.total_count
  end
end
json.message @message || 'ok'