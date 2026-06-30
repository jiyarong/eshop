class ApplicationController < ActionController::Base
  include Devise::Controllers::Helpers

  helper_method :current_user, :user_signed_in?, :can?, :available_locales, :current_locale, :user_time_zone

  prepend_before_action :set_locale
  before_action :redirect_guest_with_locale, if: :html_request?
  around_action :set_current_user

  before_action do
    next if params[:format].present?

    request.format = request.headers["Accept"].to_s.include?("text/html") ? :html : :json
  end
  before_action :authenticate_user!, if: :html_request?

  private

  def set_current_user
    Current.user = current_user
    yield
  ensure
    Current.user = nil
  end

  def set_locale
    if params[:locale].present? && available_locales.include?(params[:locale].to_sym)
      cookies.signed[:locale] = {
        value: params[:locale],
        expires: 1.year.from_now,
        same_site: :lax
      }
    end

    I18n.locale = current_locale
  end

  def current_locale
    locale = cookies.signed[:locale].presence&.to_sym
    available_locales.include?(locale) ? locale : I18n.default_locale
  end

  def available_locales
    I18n.available_locales
  end

  def redirect_guest_with_locale
    return if user_signed_in?
    return if devise_controller?
    return unless params[:locale].present? && available_locales.include?(params[:locale].to_sym)

    redirect_to new_user_session_path(locale: params[:locale])
  end

  def html_request?
    request.format.html?
  end

  def can?(permission)
    current_user&.can?(permission)
  end

  def user_time_zone
    User.profile_time_zone(current_user&.time_zone)
  end

  def user_today
    Time.current.in_time_zone(user_time_zone).to_date
  end

  def parse_user_date(value)
    return if value.blank?

    Date.iso8601(value.to_s)
  rescue Date::Error, ArgumentError
    nil
  end

  def time_in_user_zone(value, boundary)
    date = parse_user_date(value)
    return unless date

    time_for_user_date(date).public_send(boundary)
  end

  def user_date_range(from_date, to_date)
    time_for_user_date(from_date).beginning_of_day..time_for_user_date(to_date).end_of_day
  end

  def user_time_zone_sql
    ActiveRecord::Base.connection.quote(user_time_zone.tzinfo.name)
  end

  def time_for_user_date(date)
    user_time_zone.local(date.year, date.month, date.day)
  end

  def require_permission!(permission)
    return if can?(permission)

    render plain: "Forbidden", status: :forbidden
  end

  def require_any_permission!(*permissions)
    return if permissions.any? { |permission| can?(permission) }

    render plain: "Forbidden", status: :forbidden
  end
end
