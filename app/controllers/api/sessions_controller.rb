module Api
  class SessionsController < BaseController
    skip_before_action :authenticate_access_token!, only: :create

    def create
      user = User.find_for_database_authentication(email: params[:email])

      unless user&.valid_password?(params[:password]) && user.active_for_authentication?
        render json: { success: false, error: "invalid_credentials" }, status: :unauthorized
        return
      end

      raw_token, = UserAccessToken.generate_for!(user)
      render json: {
        success: true,
        data: {
          token: raw_token,
          token_type: "Bearer",
          profile: profile_json(user)
        }
      }
    end

    def destroy
      @current_access_token.destroy!
      render json: { success: true }
    end
  end
end
