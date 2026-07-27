module ErpAI
  class SqlQueriesController < ActionController::API
    include ErpAI::RequestAuthenticatable

    def create
      result = ErpAI::SqlQuery.new(
        sql: params[:sql],
        limit: params[:limit],
        offset: params[:offset]
      ).call
      render json: result, status: result[:success] ? :ok : :unprocessable_entity
    end
  end
end
