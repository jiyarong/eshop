json.success true
json.data do
  json.seller_accounts do
    json.array! @seller_accounts do |seller_account|
      json.id seller_account.id
      json.name seller_account.name
      json.token_type seller_account.token_type
      json.is_active seller_account.is_active
      json.created_at seller_account.created_at
    end
  end
  json.meta do
    json.current_page @seller_accounts.current_page
    json.total_pages  @seller_accounts.total_pages
    json.total_count  @seller_accounts.total_count
  end
end
json.message @message || 'ok'