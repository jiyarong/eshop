module Users
  class PasswordsController < Devise::PasswordsController
    layout "application"

    skip_before_action :authenticate_user!, only: [:new, :create, :edit, :update]
    before_action :normalize_email_param, only: :create

    private

    def normalize_email_param
      params[resource_name][:email] = User.normalize_email(params.dig(resource_name, :email)) if params.dig(resource_name, :email)
    end
  end
end
