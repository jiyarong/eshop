json.success true
json.data do
  json.seller_account do
      json.id @seller_account.id
      json.name @seller_account.name
      json.token_type @seller_account.token_type
      json.token_expires_at @seller_account.token_expires_at
      json.is_active @seller_account.is_active
      json.created_at @seller_account.created_at
      json.updated_at @seller_account.updated_at
  end
end
json.message @message || 'ok'
