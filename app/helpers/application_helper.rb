module ApplicationHelper
  def display_time(value, format: "%Y-%m-%d %H:%M")
    return "-" if value.blank?

    value.in_time_zone(user_time_zone).strftime(format)
  end

  def user_time_zone
    User.profile_time_zone(current_user&.time_zone)
  end
end
