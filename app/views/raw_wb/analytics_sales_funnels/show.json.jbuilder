json.success true
json.data do
  json.analytics_sales_funnel do
      json.id @analytics_sales_funnel.id
      json.account_id @analytics_sales_funnel.account_id
      json.stat_date @analytics_sales_funnel.stat_date
      json.nm_id @analytics_sales_funnel.nm_id
      json.vendor_code @analytics_sales_funnel.vendor_code
      json.brand @analytics_sales_funnel.brand
      json.subject @analytics_sales_funnel.subject
      json.open_card @analytics_sales_funnel.open_card
      json.add_to_cart @analytics_sales_funnel.add_to_cart
      json.orders @analytics_sales_funnel.orders
      json.orders_sum @analytics_sales_funnel.orders_sum
      json.buyouts @analytics_sales_funnel.buyouts
      json.buyouts_sum @analytics_sales_funnel.buyouts_sum
      json.cancel_count @analytics_sales_funnel.cancel_count
      json.cancel_sum @analytics_sales_funnel.cancel_sum
      json.conv_to_cart @analytics_sales_funnel.conv_to_cart
      json.cart_to_order @analytics_sales_funnel.cart_to_order
  end
end
json.message @message || 'ok'
