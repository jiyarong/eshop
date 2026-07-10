module Api
  class BaseController < ActionController::API
    before_action :authenticate_access_token!

    attr_reader :current_user

    private

    def authenticate_access_token!
      @current_access_token = UserAccessToken.authenticate(bearer_token)
      @current_user = @current_access_token&.user
      return if current_user

      render json: { success: false, error: "unauthorized" }, status: :unauthorized
    end

    def bearer_token
      scheme, token = request.authorization.to_s.split(" ", 2)
      token if scheme&.casecmp?("Bearer")
    end

    def profile_json(user)
      {
        id: user.id,
        name: user.name,
        email: user.email,
        time_zone: user.time_zone,
        avatar_url: user.avatar.attached? ? url_for(user.avatar) : nil
      }
    end
  end
end
