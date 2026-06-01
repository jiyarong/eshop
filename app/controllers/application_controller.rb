class ApplicationController < ActionController::Base
  include Devise::Controllers::Helpers

  helper_method :current_user, :user_signed_in?, :can?

  before_action do
    next if params[:format].present?

    request.format = request.headers["Accept"].to_s.include?("text/html") ? :html : :json
  end
  before_action :authenticate_user!, if: :html_request?

  private

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
