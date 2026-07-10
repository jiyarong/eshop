module Reports
  class ToolsController < ApplicationController
    helper_method :current_locale_params, :tool_index_filters

    before_action -> { require_permission!(:view_reports) }
    before_action :ensure_default_tool_definition!

    def index
      @tool_type_options = selectable_tool_definitions
      @tool_configurations = filtered_tool_configurations.order(updated_at: :desc)
      @tool_drawer_src = initial_tool_drawer_src
    end

    def new
      @tool_definitions = selectable_tool_definitions
      if turbo_frame_request?
        render :new_modal
      else
        render :new
      end
    end

    def show_latest
      definition = Ec::ToolDefinition.latest_active_for(params[:tool_type]) || Ec::ToolDefinition.latest_for(params[:tool_type])
      raise ActiveRecord::RecordNotFound if definition.nil?

      redirect_to report_tool_version_path(definition.tool_type, definition.version, current_locale_params)
    end

    def show_definition
      @tool_definition = Ec::ToolDefinition.find_by!(tool_type: params[:tool_type], version: params[:version])
      @renderer_partial = Reports::ToolRendererResolver.new(@tool_definition).partial_path
      @tool_configuration = nil
      @tool_library_configurations = Ec::ToolConfiguration.includes(:created_by).where(tool_definition: @tool_definition).order(updated_at: :desc)
      @can_overwrite = false
      render :show
    end

    def renderer_source
      render html: File.read(Reports::ToolRendererResolver.source_path_for(params[:renderer_key])).html_safe, layout: false
    end

    private

    def ensure_default_tool_definition!
      Ec::ToolDefinitionBootstrap.call(current_user)
    end

    def current_locale_params
      params[:locale].present? ? { locale: params[:locale] } : {}
    end

    def initial_tool_drawer_src
      if params[:tool_configuration_id].present?
        configuration = Ec::ToolConfiguration.find_by(id: params[:tool_configuration_id])
        return report_tool_configuration_path(configuration, current_locale_params) if configuration.present?
      end

      return if params[:tool_type].blank?

      definition =
        if params[:version].present?
          Ec::ToolDefinition.find_by(tool_type: params[:tool_type], version: params[:version])
        else
          Ec::ToolDefinition.latest_active_for(params[:tool_type]) || Ec::ToolDefinition.latest_for(params[:tool_type])
        end

      return if definition.nil?

      report_tool_version_path(definition.tool_type, definition.version, current_locale_params)
    end

    def selectable_tool_definitions
      Ec::ToolDefinition.order(:tool_type, version: :desc).group_by(&:tool_type).values.map do |definitions|
        definitions.find(&:active?) || definitions.first
      end
    end

    def tool_index_filters
      @tool_index_filters ||= {
        q: params[:q].to_s.strip,
        tool_type: params[:tool_type].to_s.strip,
        version: params[:version].to_s.strip,
        creator: params[:creator].to_s.strip
      }
    end

    def filtered_tool_configurations
      scope = Ec::ToolConfiguration.joins(:tool_definition, :created_by).includes(:tool_definition, :created_by)
      filters = tool_index_filters

      if filters[:q].present?
        q = "%#{filters[:q]}%"
        scope = scope.where(
          "ec_tool_configurations.name ILIKE :q OR ec_tool_definitions.tool_type ILIKE :q OR users.email ILIKE :q",
          q: q
        )
      end

      if filters[:tool_type].present?
        scope = scope.where(ec_tool_definitions: { tool_type: filters[:tool_type] })
      end

      if filters[:version].present?
        scope = scope.where(ec_tool_definitions: { version: filters[:version].to_i })
      end

      if filters[:creator].present?
        scope = scope.where("users.email ILIKE ?", "%#{filters[:creator]}%")
      end

      scope
    end
  end
end
