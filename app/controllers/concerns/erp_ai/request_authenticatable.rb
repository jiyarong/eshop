module ErpAI
  module RequestAuthenticatable
    extend ActiveSupport::Concern

    CURRENT_USER_ENV = "eshop_manage.erp_ai_request.current_user".freeze

    included do
      before_action :authenticate_erp_ai_request!
    end

    private

    def authenticate_erp_ai_request!
      @current_user = request.env[CURRENT_USER_ENV]
      return if @current_user

      @current_user = UserApiKey.authenticate(bearer_token)
      return if @current_user&.can?(:view_reports)

      render json: { error: "Unauthorized" }, status: :unauthorized
    end

    def bearer_token
      header = request.headers["Authorization"].to_s
      return unless header.start_with?("Bearer ")

      header.delete_prefix("Bearer ").strip
    end
  end
end
