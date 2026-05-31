json.success true
json.data do
  json.analytics_sales_funnels do
    json.array! @analytics_sales_funnels do |item|
      json.id item.id
      json.account_id item.account_id
      json.stat_date item.stat_date
      json.nm_id item.nm_id
      json.vendor_code item.vendor_code
      json.brand item.brand
      json.subject item.subject
      json.open_card item.open_card
      json.add_to_cart item.add_to_cart
      json.orders item.orders
      json.orders_sum item.orders_sum
      json.buyouts item.buyouts
      json.buyouts_sum item.buyouts_sum
      json.cancel_count item.cancel_count
      json.cancel_sum item.cancel_sum
      json.conv_to_cart item.conv_to_cart
      json.cart_to_order item.cart_to_order
      json.avg_price item.avg_price
      json.avg_orders_per_day item.avg_orders_per_day
      json.share_order_percent item.share_order_percent
      json.add_to_wishlist item.add_to_wishlist
      json.localization_percent item.localization_percent
      json.buyout_percent item.buyout_percent
      json.time_to_ready_days item.time_to_ready_days
      json.time_to_ready_hours item.time_to_ready_hours
      json.time_to_ready_mins item.time_to_ready_mins
    end
  end
  json.meta do
    json.current_page @analytics_sales_funnels.current_page
    json.total_pages @analytics_sales_funnels.total_pages
    json.total_count @analytics_sales_funnels.total_count
  end
end
json.message @message || 'ok'