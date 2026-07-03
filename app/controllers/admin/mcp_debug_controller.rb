module Admin
  class McpDebugController < BaseController
    def show
      load_debug_context
      @result = execute_tool if params[:run].present?
    rescue StandardError => e
      @error = e.message
    end

    def create
      redirect_to admin_mcp_debug_path(
        user_id: params[:user_id],
        tool_name: params[:tool_name],
        tool_arguments: raw_tool_arguments,
        run: "1"
      )
    end

    private

    def load_debug_context
      @users = User.order(:email)
      @tools = Mcp::ToolRegistry.new(current_user: current_user).definitions
      @selected_user_id ||= params[:user_id].presence || @users.first&.id
      @selected_tool_name ||= params[:tool_name].presence || @tools.first&.fetch(:name)
      @selected_tool = selected_tool
      @tool_arguments ||= clean_tool_arguments(raw_tool_arguments)
    end

    def execute_tool
      user = User.find(@selected_user_id)

      Mcp::ToolExecutor.new(current_user: user).call(@selected_tool_name.to_s, @tool_arguments)
    end

    def selected_tool
      @tools.find { |tool| tool.fetch(:name) == @selected_tool_name } || @tools.first
    end

    def clean_tool_arguments(arguments)
      arguments.each_with_object({}) do |(key, value), cleaned|
        next if value.blank?

        cleaned[key] = cast_argument_value(key, value)
      end
    end

    def cast_argument_value(key, value)
      schema = @selected_tool&.dig(:inputSchema, :properties, key.to_sym) ||
        @selected_tool&.dig(:inputSchema, :properties, key.to_s)
      return value unless schema&.fetch(:type, nil) == "integer"

      value.to_i
    end

    def raw_tool_arguments
      params[:tool_arguments].respond_to?(:to_unsafe_h) ? params[:tool_arguments].to_unsafe_h : {}
    end
  end
end
