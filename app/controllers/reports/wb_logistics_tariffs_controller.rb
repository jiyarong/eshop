module Reports
  class WbLogisticsTariffsController < ApplicationController
    before_action -> { require_permission!(:view_reports) }

    def index
      delivery_mode = params[:delivery_mode].to_s.downcase.presence || "fbo"
      date = Date.iso8601(params[:date].to_s) rescue Date.current
      result = RawWb::LogisticsTariffQuery.run(
        date: date,
        delivery_mode: delivery_mode,
        warehouse: params[:warehouse],
        geo: params[:geo]
      )

      render json: {
        source: {
          account_id: result[:account_id],
          snapshot_id: result[:snapshot_id],
          requested_date: result[:requested_date],
          effective_from: result[:effective_from],
          effective_to: result[:effective_to]
        },
        delivery_mode: result[:delivery_mode],
        rows: result[:rows],
        filter: {
          matched_count: result[:matched_count],
          average_logistics_coeff: result[:average_logistics_coeff],
          average_base_rub: result[:average_base_rub],
          average_liter_rub: result[:average_liter_rub]
        }
      }
    rescue ArgumentError => error
      render json: { errors: [error.message] }, status: :unprocessable_entity
    rescue RawWb::LogisticsTariffQuery::NoAccountError
      render json: { errors: ["wb_api_token_unavailable"] }, status: :unprocessable_entity
    rescue RawWb::LogisticsTariffQuery::NoSnapshotError
      render json: { errors: ["wb_logistics_tariff_snapshot_unavailable"] }, status: :unprocessable_entity
    rescue RawWb::LogisticsTariffQuery::InvalidResponseError
      render json: { errors: ["wb_logistics_tariffs_invalid_response"] }, status: :bad_gateway
    rescue RawWb::WbClient::ApiError, RawWb::WbClient::RetryableError
      render json: { errors: ["wb_logistics_tariffs_unavailable"] }, status: :bad_gateway
    end
  end
end
