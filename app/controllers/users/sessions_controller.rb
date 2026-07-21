module Users
  class SessionsController < Devise::SessionsController
    layout "auth"

    skip_before_action :authenticate_user!, only: [:new, :create]
    before_action :normalize_email_param, only: :create

    private

    def normalize_email_param
      params[resource_name][:email] = User.normalize_email(params.dig(resource_name, :email)) if params.dig(resource_name, :email)
    end
  end
end
