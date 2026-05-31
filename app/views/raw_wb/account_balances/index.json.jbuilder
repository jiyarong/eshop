json.success true
json.data do
  json.account_balances do
    json.array! @account_balances do |account_balance|
      json.id account_balance.id
      json.currency account_balance.currency
      json.current account_balance.current
      json.for_withdraw account_balance.for_withdraw
      json.snapshot_at account_balance.snapshot_at
    end
  end
  json.meta do
    json.current_page @account_balances.current_page
    json.total_pages @account_balances.total_pages
    json.total_count @account_balances.total_count
  end
end
json.message @message || 'ok'