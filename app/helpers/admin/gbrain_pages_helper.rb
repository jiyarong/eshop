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
