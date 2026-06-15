module Users
  class SessionsController < Devise::SessionsController
    layout "auth"

    skip_before_action :authenticate_user!, only: [:new, :create]
  end
end
