module Users
  class PasswordsController < Devise::PasswordsController
    layout "application"

    skip_before_action :authenticate_user!, only: [:new, :create, :edit, :update]
  end
end
