class McpController < ActionController::API
  before_action :authenticate_api_key!

  def create
    response = Mcp::Server.new(current_user: @current_user).call(request.request_parameters)

    render json: response
  rescue JSON::ParserError
    render json: jsonrpc_error(nil, -32700, "Parse error"), status: :bad_request
  rescue Mcp::Server::UnsupportedMethodError => e
    render json: jsonrpc_error(request.request_parameters["id"], -32601, e.message)
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

  def jsonrpc_error(id, code, message)
    {
      jsonrpc: "2.0",
      id: id,
      error: {
        code: code,
        message: message
      }
    }
  end
end
