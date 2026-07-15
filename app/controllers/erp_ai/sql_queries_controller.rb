module ErpAI
  class SqlQueriesController < ActionController::API
    before_action :authenticate_api_key!

    def create
      result = ErpAI::SqlQuery.new(
        sql: params[:sql],
        limit: params[:limit],
        offset: params[:offset]
      ).call
      render json: result, status: result[:success] ? :ok : :unprocessable_entity
    end

    private

    def authenticate_api_key!
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
