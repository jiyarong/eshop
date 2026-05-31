json.success true
json.data do
  json.product_price do
      json.id @product_price.id
      json.product_id @product_price.product_id
      json.account_id @product_price.account_id
      json.price @product_price.price
      json.discount @product_price.discount
      json.club_discount @product_price.club_discount
      json.final_price @product_price.final_price
      json.is_in_quarantine @product_price.is_in_quarantine
      json.updated_at @product_price.updated_at
  end
end
json.message @message || 'ok'
