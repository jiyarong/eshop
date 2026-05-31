json.success true
json.data do
  json.account_balance do
      json.id @account_balance.id
      json.account_id @account_balance.account_id
      json.currency @account_balance.currency
      json.current @account_balance.current
      json.for_withdraw @account_balance.for_withdraw
      json.snapshot_at @account_balance.snapshot_at
  end
end
json.message @message || 'ok'
