module ApplicationHelper
  def inventory_pagination_items(page, page_count, sibling_count: 1)
    visible_count = sibling_count * 2 + 5
    return (1..page_count).to_a if page_count <= visible_count

    items = [1]
    window_start = [2, page - sibling_count].max
    window_end = [page_count - 1, page + sibling_count].min

    items << :ellipsis_left if window_start > 2
    items.concat((window_start..window_end).to_a)
    items << :ellipsis_right if window_end < page_count - 1
    items << page_count
  end

  def inventory_pagination_summary(scope)
    total_count = scope.total_count.to_i
    return t("reports.inventory.pagination.summary", from: 0, to: 0, total: 0) if total_count.zero?

    from = scope.offset_value.to_i + 1
    to = [scope.offset_value.to_i + scope.limit_value.to_i, total_count].min

    t("reports.inventory.pagination.summary", from: from, to: to, total: total_count)
  end

  def inventory_pagination_page_chip(scope)
    t("reports.inventory.pagination.page_chip", page: scope.current_page, pages: scope.total_pages)
  end

  def sku_pagination_summary(scope)
    total_count = scope.total_count.to_i
    return t("erp.skus.pagination.summary", from: 0, to: 0, total: 0) if total_count.zero?

    from = scope.offset_value.to_i + 1
    to = [scope.offset_value.to_i + scope.limit_value.to_i, total_count].min

    t("erp.skus.pagination.summary", from: from, to: to, total: total_count)
  end

  def sku_pagination_page_chip(scope)
    t("erp.skus.pagination.page_chip", page: scope.current_page, pages: scope.total_pages)
  end

  def display_time(value, format: "%Y-%m-%d %H:%M")
    return "-" if value.blank?

    value.in_time_zone(user_time_zone).strftime(format)
  end

  def inventory_dimensions_text(length_cm, width_cm, height_cm)
    return if [length_cm, width_cm, height_cm].any?(&:blank?)

    t(
      "reports.inventory.labels.dimensions_cm",
      length: inventory_dimension_value(length_cm),
      width: inventory_dimension_value(width_cm),
      height: inventory_dimension_value(height_cm)
    )
  end

  def inventory_estimated_volume_text(quantity, unit_volume_l)
    return if unit_volume_l.blank? || unit_volume_l.to_d <= 0

    estimated_volume_m3 = quantity.to_d * unit_volume_l.to_d / 1000
    t("reports.inventory.labels.estimated_volume_m3", volume: format("%.4f", estimated_volume_m3))
  end

  def inventory_volume_m3_text(volume_m3)
    t("reports.inventory.labels.estimated_volume_m3", volume: format("%.4f", volume_m3.to_d))
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

  private

  def inventory_dimension_value(value)
    value.to_d.to_s("F").sub(/\.0+\z/, "").sub(/(\.\d*?)0+\z/, '\1')
  end
end
