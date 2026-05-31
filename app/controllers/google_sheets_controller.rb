class GoogleSheetsController < ApplicationController
  skip_before_action :verify_authenticity_token, raise: false
  before_action :verify_webhook_secret, only: [:webhook]

  def ping
    GoogleSheets::PingService.new.call
    render json: { success: true, message: "Google Sheets 连通成功", time: Time.current }
  rescue => e
    render json: { success: false, message: e.message }, status: :internal_server_error
  end

  def webhook
    payload = JSON.parse(request.body.read)
    sheet   = payload["sheet"].to_s

    result = case sheet
             when "SKU"
               GoogleSheets::SkuImportService.new.call
             when "SKU_COST"
               GoogleSheets::SkuCostImportService.new.call
             when "WB_COST", "OZON_COST"
               GoogleSheets::PlatformCostImportService.new.call
             when "Inventory"
               GoogleSheets::InventorySnapshotImportService.new.call
             else
               { skipped: true, sheet: sheet }
             end

    Rails.logger.info("[GoogleSheets Webhook] sheet=#{sheet} result=#{result.inspect}")
    render json: { success: true, sheet: sheet, result: result }
  rescue => e
    Rails.logger.error("[GoogleSheets Webhook] #{e.message}")
    render json: { success: false, message: e.message }, status: :bad_request
  end

  private

  def verify_webhook_secret
    expected = ENV["GOOGLE_SHEETS_WEBHOOK_SECRET"]
    received = request.headers["X-Webhook-Secret"]
    return if expected.present? && ActiveSupport::SecurityUtils.secure_compare(expected, received.to_s)

    render json: { success: false, message: "Unauthorized" }, status: :unauthorized
  end
end
