module Reports
  class ToolConfigurationsController < ApplicationController
    helper_method :current_locale_params

    before_action -> { require_permission!(:view_reports) }
    before_action :load_tool_configuration, only: [:show, :edit, :update]

    def show
      render "reports/tools/show"
    end

    def edit
      render "reports/tools/show"
    end

    def create
      tool_configuration = Ec::ToolConfiguration.new(tool_configuration_params)
      tool_configuration.created_by = current_user

      if tool_configuration.save
        render json: { success: true, id: tool_configuration.id, show_path: report_tool_configuration_path(tool_configuration) }, status: :ok
      else
        render json: { success: false, errors: tool_configuration.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def update
      return render plain: "Forbidden", status: :forbidden unless owner?(@tool_configuration)

      if @tool_configuration.update(tool_configuration_params)
        render json: { success: true, id: @tool_configuration.id, show_path: report_tool_configuration_path(@tool_configuration) }, status: :ok
      else
        render json: { success: false, errors: @tool_configuration.errors.full_messages }, status: :unprocessable_entity
      end
    end

    private

    def load_tool_configuration
      @tool_configuration = Ec::ToolConfiguration.includes(:tool_definition, :created_by).find(params[:id])
      @tool_definition = @tool_configuration.tool_definition
      @renderer_partial = Reports::ToolRendererResolver.new(@tool_definition).partial_path
      @tool_library_configurations = Ec::ToolConfiguration.includes(:created_by).where(tool_definition: @tool_definition).order(updated_at: :desc)
      @can_overwrite = owner?(@tool_configuration)
    end

    def tool_configuration_params
      params.require(:ec_tool_configuration).permit(:tool_definition_id, :name, :active, config_json: {})
    end

    def owner?(tool_configuration)
      tool_configuration.created_by_id == current_user&.id
    end

    def current_locale_params
      params[:locale].present? ? { locale: params[:locale] } : {}
    end
  end
end
