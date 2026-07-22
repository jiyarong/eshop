module ErpAI
  class WeeklyProfitReportsController < ActionController::API
    before_action :authenticate_api_key!

    def create
      report = ::WeeklyProfitReports::ReportQueryRunner.run(params: params, today: user_today)

      render json: { success: true, data: report, message: "ok" }
    rescue ActionController::ParameterMissing => e
      render_error(e.message, :bad_request)
    rescue ActiveRecord::RecordNotFound
      render_error(error_message_for("store_not_found"), :not_found)
    rescue ArgumentError => e
      status = case e.message
      when "invalid_week_range", "current_week_unsupported", "missing_weekly_rate"
        :unprocessable_entity
      else
        :bad_request
      end
      render_error(error_message_for(e.message), status)
    rescue => e
      Rails.logger.error("[ErpAI::WeeklyProfitReports] #{e.class}: #{e.message}")
      render_error("internal server error", :internal_server_error)
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

    def user_today
      Time.current.in_time_zone(User.profile_time_zone(@current_user&.time_zone)).to_date
    end

    def render_error(message, status)
      render json: { success: false, message: message }, status: status
    end

    def error_message_for(code)
      case code
      when "invalid_report_type"
        I18n.t("weekly_profit_reports.errors.invalid_report_type")
      when "invalid_store_ref"
        I18n.t("weekly_profit_reports.errors.invalid_store_ref")
      when "store_not_found"
        I18n.t("weekly_profit_reports.errors.store_not_found")
      when "invalid_date"
        I18n.t("weekly_profit_reports.errors.invalid_date")
      when "invalid_week_range"
        I18n.t("weekly_profit_reports.errors.invalid_week_range")
      when "current_week_unsupported"
        I18n.t("weekly_profit_reports.errors.current_week_unsupported")
      when "missing_weekly_rate"
        I18n.t("weekly_profit_reports.errors.missing_weekly_rate")
      else
        code
      end
    end
  end
end
