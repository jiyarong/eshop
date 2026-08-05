module Reports
  class SupplyOrdersController < ApplicationController
    include SpuSkuFilterable
    include ResponsibleUserFilterable

    before_action -> { require_permission!(:view_reports) }
    helper_method :supply_order_columns, :supply_order_value, :supply_order_status_options

    def show
      return render_index if request.format.html? && request.headers["Turbo-Frame"].blank?

      @report = query.call
      respond_to do |format|
        format.html { render partial: "reports/supply_orders/results" }
        format.json { render json: { success: true, data: @report, message: "ok" } }
      end
    rescue ActiveRecord::RecordNotFound
      render_error(t("supply_order_reports.errors.store_not_found"), :not_found)
    rescue ActionController::ParameterMissing, ArgumentError => e
      render_error(t("supply_order_reports.errors.#{e.message}", default: e.message), :unprocessable_entity)
    end

    private

    def render_index
      @store_options = SupplyOrderReports::ReportQuery.store_options
      @selected_store_ref = params[:store_ref].presence || @store_options.first&.dig(:ref)
      @selected_platform = @selected_store_ref.to_s.split(":", 2).first
      @selected_statuses = query.selected_statuses(@selected_platform)
      load_responsible_user_filters
      load_spu_sku_filter(selected_sku_codes: query.selected_direct_sku_codes)
      if params[:store_ref].blank? && @selected_store_ref.present?
        redirect_to reports_supply_orders_path(store_ref: @selected_store_ref, master_sku_ids: @spu_sku_selected_master_sku_ids.presence, sku_codes: @spu_sku_selected_sku_codes.presence, operator_id: @operator_id) and return
      end
      @report = query.call if @selected_store_ref.present?
      render :show
    end

    def query
      @query ||= SupplyOrderReports::ReportQuery.new(params: params)
    end

    def supply_order_columns(report)
      report.dig(:meta, :columns).map { |key| [key, t("supply_order_reports.columns.#{report.dig(:meta, :platform)}.#{key}")] }
    end

    def supply_order_status_options
      values = @selected_platform == "wb" ? SupplyOrderReports::ReportQuery::WB_STATUSES : SupplyOrderReports::ReportQuery::OZON_STATUSES
      values.map { |value| [value.to_s, t("supply_order_reports.statuses.#{@selected_platform}.#{value}", default: value.to_s.humanize)] }
    end

    def supply_order_value(row, key)
      value = row[key]
      return supply_order_packaging_value(row) if key == :packaging && row[:pallet]
      return "-" if value.nil? || value == ""
      return t("supply_order_reports.statuses.wb.#{value}", default: value) if key == :status && value.is_a?(Integer)
      return t("supply_order_reports.statuses.ozon.#{value}", default: value.to_s.humanize) if key == :status
      return supply_order_packaging_value(row) if key == :packaging
      return t(value ? "shared.yes" : "shared.no", default: value ? "Yes" : "No") if %i[pallet can_show_quantity].include?(key)
      return helpers.display_time(value) if %i[created_at scheduled_at actual_at state_updated_at synced_at].include?(key)
      return format_timeslot(value) if key == :timeslot
      value
    end

    def supply_order_packaging_value(row)
      type = if row[:pallet]
        "piece_pallet"
      else
        SupplyOrderReports::ReportQuery::WB_PACKAGING_TYPES[row[:packaging].to_i]
      end
      return t("supply_order_reports.packaging.#{type}") if type.present?

      t("supply_order_reports.packaging.unknown", id: row[:packaging])
    end

    def format_timeslot(value)
      slot = value.is_a?(Hash) ? (value["timeslot"] || value) : {}
      from = slot["from"] || slot["date_from"]
      to = slot["to"] || slot["date_to"]
      [from, to].compact.map { |time| helpers.display_time(time) }.join(" ~ ").presence || "-"
    end

    def render_error(message, status)
      respond_to do |format|
        format.html { render partial: "reports/supply_orders/error", locals: { message: message }, status: status }
        format.json { render json: { success: false, message: message }, status: status }
      end
    end
  end
end
