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

  def sku_product_pagination_summary(scope)
    total_count = scope.total_count.to_i
    return t("erp.sku_products.pagination.summary", from: 0, to: 0, total: 0) if total_count.zero?

    from = scope.offset_value.to_i + 1
    to = [scope.offset_value.to_i + scope.limit_value.to_i, total_count].min
    t("erp.sku_products.pagination.summary", from: from, to: to, total: total_count)
  end

  def sku_product_pagination_page_chip(scope)
    t("erp.sku_products.pagination.page_chip", page: scope.current_page, pages: scope.total_pages)
  end

  def sku_batch_pagination_summary(scope)
    total_count = scope.total_count.to_i
    return t("erp.sku_batches.pagination.summary", from: 0, to: 0, total: 0) if total_count.zero?

    from = scope.offset_value.to_i + 1
    to = [scope.offset_value.to_i + scope.limit_value.to_i, total_count].min

    t("erp.sku_batches.pagination.summary", from: from, to: to, total: total_count)
  end

  def sku_batch_pagination_page_chip(scope)
    t("erp.sku_batches.pagination.page_chip", page: scope.current_page, pages: scope.total_pages)
  end

  def spu_pagination_summary(scope)
    total_count = scope.total_count.to_i
    return t("erp.spus.pagination.summary", from: 0, to: 0, total: 0) if total_count.zero?

    from = scope.offset_value.to_i + 1
    to = [scope.offset_value.to_i + scope.limit_value.to_i, total_count].min

    t("erp.spus.pagination.summary", from: from, to: to, total: total_count)
  end

  def spu_pagination_page_chip(scope)
    t("erp.spus.pagination.page_chip", page: scope.current_page, pages: scope.total_pages)
  end

  def sku_developer_names(sku)
    user_display_names(sku.developers)
  end

  def sku_operator_names(sku)
    user_display_names(sku.sku_products.flat_map(&:operators))
  end

  def operator_sku_metric_value(value, type: :number)
    return t("operator_skus.values.unavailable") if value.nil?

    case type
    when :currency
      number_to_currency(value, unit: "¥", precision: 2)
    when :percentage
      number_to_percentage(value, precision: 2)
    when :days
      t("operator_skus.values.days", count: format("%.1f", value))
    else
      number_with_delimiter(value)
    end
  end

  def operator_sku_comparison_text(comparison)
    delta_pct = comparison&.dig(:delta_pct) || comparison&.dig("delta_pct")
    return t("operator_skus.values.unavailable") if delta_pct.nil?

    arrow = delta_pct.to_d.positive? ? "↑" : (delta_pct.to_d.negative? ? "↓" : "→")
    t("operator_skus.values.comparison", arrow: arrow, value: format("%.2f", delta_pct.to_d.abs))
  end

  def operator_sku_comparison_class(comparison)
    case comparison&.dig(:semantic) || comparison&.dig("semantic")
    when "positive" then "is-positive"
    when "negative" then "is-negative"
    else "is-neutral"
    end
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

  def ai_inventory_health_severity_class(severity)
    case severity.to_s.downcase
    when "green", "success"
      "success"
    when "yellow", "warning", "warn"
      "warning"
    when "orange"
      "orange"
    when "red", "error", "critical", "danger"
      "danger"
    when "info", "blue"
      "info"
    else
      "neutral"
    end
  end

  def ai_inventory_health_metric_value(value)
    value.is_a?(Hash) || value.is_a?(Array) ? JSON.generate(value) : value
  end

  def ai_operation_action_diagnosis?(diagnosis)
    diagnosis.data.to_h["diagnosis_kind"] == "operation_action_effect"
  end

  def ai_operation_action_effect_label(effect)
    t("reports.sku_detail.ai_operation_diagnosis.effects.#{effect}")
  end

  def ai_operation_action_confidence_label(confidence)
    t("reports.sku_detail.ai_operation_diagnosis.confidence_levels.#{confidence}")
  end

  def ai_operation_action_type_label(operation_type)
    t("erp.operation_actions.operation_types.#{operation_type}")
  end

  def user_time_zone
    User.profile_time_zone(current_user&.time_zone)
  end

  def user_display_names(users)
    users
      .compact
      .uniq(&:id)
      .sort_by { |user| user.display_name.downcase }
      .map(&:display_name)
      .join(", ")
      .presence
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
