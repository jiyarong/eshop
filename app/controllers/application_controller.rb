class ApplicationController < ActionController::Base
  include Devise::Controllers::Helpers

  helper_method :current_user, :user_signed_in?, :can?, :available_locales, :current_locale

  prepend_before_action :set_locale
  before_action :redirect_guest_with_locale, if: :html_request?

  before_action do
    next if params[:format].present?

    request.format = request.headers["Accept"].to_s.include?("text/html") ? :html : :json
  end
  before_action :authenticate_user!, if: :html_request?

  private

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

  def require_permission!(permission)
    return if can?(permission)

    render plain: "Forbidden", status: :forbidden
  end

  def require_any_permission!(*permissions)
    return if permissions.any? { |permission| can?(permission) }

    render plain: "Forbidden", status: :forbidden
  end
end
