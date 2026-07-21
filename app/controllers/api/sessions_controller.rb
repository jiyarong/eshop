module Api
  class SessionsController < BaseController
    skip_before_action :authenticate_access_token!, only: :create

    def create
      user = User.find_for_database_authentication(email: User.normalize_email(params[:email]))

      unless user&.valid_password?(params[:password]) && user.active_for_authentication?
        render json: { success: false, error: "invalid_credentials" }, status: :unauthorized
        return
      end

      Sub2UserApiKeyProvisioner.call(user: user) unless user.sub2_user_api_key
      raw_token, = UserAccessToken.generate_for!(user)
      render json: {
        success: true,
        data: {
          token: raw_token,
          token_type: "Bearer",
          profile: profile_json(user)
        }
      }
    rescue Sub2UserApiKeyProvisioner::Error => error
      Rails.logger.error("Sub2 API key provisioning failed during login for user #{user.id}: #{error.message}")
      render json: { success: false, error: "sub2_api_key_provisioning_failed" }, status: :bad_gateway
    end

    def destroy
      @current_access_token.destroy!
      render json: { success: true }
    end
  end
end
