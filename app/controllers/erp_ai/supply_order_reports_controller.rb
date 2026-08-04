module ErpAI
  class SupplyOrderReportsController < ActionController::API
    include ErpAI::RequestAuthenticatable

    PAGE_SIZE = 100

    def create
      report = SupplyOrderReports::ReportQuery.new(params: params, per_page: PAGE_SIZE).call

      render json: { success: true, data: report, message: "ok" }
    rescue ActionController::ParameterMissing => e
      render_error(e.message, :bad_request)
    rescue ActiveRecord::RecordNotFound
      render_error(I18n.t("supply_order_reports.errors.store_not_found"), :not_found)
    rescue ArgumentError => e
      render_error(error_message_for(e.message), :bad_request)
    rescue => e
      Rails.logger.error("[ErpAI::SupplyOrderReports] #{e.class}: #{e.message}")
      render_error("internal server error", :internal_server_error)
    end

    private

    def render_error(message, status)
      render json: { success: false, message: message }, status: status
    end

    def error_message_for(code)
      I18n.t("supply_order_reports.errors.#{code}", default: code)
    end
  end
end
