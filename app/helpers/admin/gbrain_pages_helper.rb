module Admin::GbrainPagesHelper
  def gbrain_status_label(status)
    t("admin.gbrain.statuses.#{status}")
  end

  def gbrain_status_class(status)
    case status
    when "synced" then "is-active"
    when "failed" then "is-danger"
    else "is-muted"
    end
  end

  def gbrain_page_type_label(page_type)
    return t("common.empty_value") if page_type.blank?

    t("admin.gbrain.page_types.#{page_type}")
  end

  def gbrain_page_type_options
    GbrainPage::PAGE_TYPES.keys.map { |page_type| [ gbrain_page_type_label(page_type), page_type ] }
  end

  def gbrain_field_error(page, attribute)
    return if page.errors[attribute].blank?

    content_tag(:small, page.errors.full_messages_for(attribute).join(t("common.list_separator")),
      class: "gbrain-field-error", role: "alert")
  end

  def gbrain_list_value(values)
    Array(values).presence&.join(", ") || t("common.empty_value")
  end

  def gbrain_source_tier_label(source_tier)
    source_tier.present? ? t("admin.gbrain.source_tiers.#{source_tier}") : t("common.empty_value")
  end

  def gbrain_confidence_label(confidence)
    confidence.present? ? t("admin.gbrain.confidence_levels.#{confidence}") : t("common.empty_value")
  end

  def formatted_gbrain_result(result)
    JSON.pretty_generate(result)
  end

  def gbrain_remote_page_title(page)
    page["title"].presence || page["slug"].presence || t("common.empty_value")
  end

  def gbrain_remote_page_time(value)
    return t("common.empty_value") if value.blank?

    display_time(Time.zone.parse(value.to_s))
  rescue ArgumentError
    value
  end

  def gbrain_remote_metadata_value(value)
    value.is_a?(Array) || value.is_a?(Hash) ? formatted_gbrain_result(value) : value
  end
end
