class ApplicationController < ActionController::API
  include ActionView::Rendering
  include ActionView::Layouts
  include ActionController::ImplicitRender
  include ActionController::MimeResponds

  before_action do
    next if params[:format].present?

    request.format = request.headers["Accept"].to_s.include?("text/html") ? :html : :json
  end
end
