module Users
  class SessionsController < Devise::SessionsController
    layout "application"

    skip_before_action :authenticate_user!, only: [:new, :create]
  end
end
