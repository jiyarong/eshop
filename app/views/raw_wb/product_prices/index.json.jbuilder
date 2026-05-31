json.success true
json.data do
  json.product_prices do
    json.array! @product_prices do |product_price|
      json.id product_price.id
      json.product_id product_price.product_id
      json.price product_price.price
      json.discount product_price.discount
      json.club_discount product_price.club_discount
      json.final_price product_price.final_price
      json.is_in_quarantine product_price.is_in_quarantine
    end
  end
  json.meta do
    json.current_page @product_prices.current_page
    json.total_pages @product_prices.total_pages
    json.total_count @product_prices.total_count
  end
end
json.message @message || 'ok'