module ApplicationHelper
  def display_time(value, format: "%Y-%m-%d %H:%M")
    return "-" if value.blank?

    value.in_time_zone(user_time_zone).strftime(format)
  end

  def user_time_zone
    User.profile_time_zone(current_user&.time_zone)
  end

  def product_edit_url(platform, platform_sku_id)
    return if platform_sku_id.blank?

    encoded_id = ERB::Util.url_encode(platform_sku_id.to_s)

    case platform.to_s
    when "ozon"
      "https://seller.ozon.ru/app/products/#{encoded_id}/edit/general-info"
    when "wb"
      "https://seller.wildberries.ru/new-goods/card?nmID=#{encoded_id}&type=EXIST_CARD"
    end
  end
end
