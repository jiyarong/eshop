json.success true
json.data do
  json.return_claim do
      json.id @return_claim.id
      json.wb_claim_id @return_claim.wb_claim_id
      json.order_id @return_claim.order_id
      json.nm_id @return_claim.nm_id
      json.status @return_claim.status
      json.reason @return_claim.reason
      json.response_text @return_claim.response_text
      json.wb_created_at @return_claim.wb_created_at
      json.responded_at @return_claim.responded_at
      json.synced_at @return_claim.synced_at
  end
end
json.message @message || 'ok'
