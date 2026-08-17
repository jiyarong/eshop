require "cgi"
require "digest"

class ReportsController < ApplicationController
  include InlineEditableResponse
  include ResponsibleUserFilterable
  include SpuSkuFilterable
  include SkuMarketingStateFilterable
  include MasterSkuCategoryFilterable
  include AIDiagnosisEventFilterable

  helper_method :report_value, :sku_sales_series_name, :sku_detail_tabs, :sku_detail_tab_path, :platform_label_for_sales, :inventory_filters_active?,
                :sku_operation_funnel_columns, :sku_operation_profit_columns, :sku_operation_report_value,
                :sku_operation_row_comparison, :sku_operation_comparison_label, :sku_operation_comparison_class,
                :sku_ads_metric, :sku_ads_comparison_label, :sku_ads_comparison_class,
                :search_terms_metric, :search_terms_metric_content, :search_terms_comparison_label, :search_terms_comparison_class,
                :sku_supply_order_columns, :sku_supply_order_value, :sku_supply_order_status_options, :warehouse_report_path
  before_action -> { require_permission!(:view_reports) }
  before_action -> { require_any_permission!(:manage_finance, :manage_skus) }, only: [:new_sku_predicted_cost, :create_sku_predicted_cost]
  before_action -> { require_permission!(:manage_skus) }, only: [:create_sku_attachment, :edit_sku_attachment, :update_sku_attachment, :new_sku_operation_action, :create_sku_operation_action, :edit_sku_operation_action, :update_sku_operation_action, :destroy_sku_operation_action, :destroy_sku_attachment, :destroy_sku_inventory_health_result]
  before_action -> { require_permission!(:manage_skus) }, only: [:update_inventory_returns]

  SKU_DETAIL_TABS = %w[sales_funnel profit inventory supply_orders warehouses operation_actions ads ai_inventory_health basic].freeze
  SKU_DETAIL_HIDDEN_TABS = %w[operation costs stores trend search_terms].freeze
  SKU_DETAIL_AVAILABLE_TABS = (SKU_DETAIL_TABS + SKU_DETAIL_HIDDEN_TABS).freeze
  OZON_WAREHOUSE_PAGE_SIZE = 10
  WB_WAREHOUSE_PAGE_SIZE = 10
  SKU_PROFIT_TREND_WEEKS = 8
  SKU_PROFIT_TREND_METRICS = %i[
    net_sales revenue ads goods_cost average_profit_per_order annualized_return_pct annualized_net_profit_cny
  ].freeze
  SKU_SALES_FUNNEL_TREND_MAX_DAYS = 366

  def inventory
    @sku_query = params[:sku].to_s.strip
    load_master_sku_category_filter
    load_spu_sku_filter
    load_sku_marketing_state_filters
    load_responsible_user_filters
    load_ai_diagnosis_event_filter
    @turnover_days_min_query = params[:turnover_days_min].to_s.strip
    @turnover_days_max_query = params[:turnover_days_max].to_s.strip
    @procurement_turnover_days_min_query = params[:procurement_turnover_days_min].to_s.strip
    @procurement_turnover_days_max_query = params[:procurement_turnover_days_max].to_s.strip
    @turnover_days_min = parse_decimal(@turnover_days_min_query)
    @turnover_days_max = parse_decimal(@turnover_days_max_query)
    @procurement_turnover_days_min = parse_decimal(@procurement_turnover_days_min_query)
    @procurement_turnover_days_max = parse_decimal(@procurement_turnover_days_max_query)
    scope = inventory_skus_scope.order(:sku_code)
    scope = apply_inventory_turnover_filter(scope)
    @inventory_volume_summary = build_inventory_volume_summary(scope)
    @inventory_rows = build_inventory_rows(scope)
  end

  def inventory_detail
    @sku = Ec::Sku.find_by!(sku_code: params[:sku_code].to_s.upcase)
    @inventory_detail = Ec::InventoryPageDetailQuery.new(
      @sku,
      detail_tab: params[:detail_tab],
      book_batch_page: params[:book_batch_page],
      return_page: params[:return_page],
      return_restockable: params[:return_restockable],
      date_to: user_today,
      time_zone: user_time_zone
    ).call

    if turbo_frame_request?
      if request.headers["Turbo-Frame"] == "inventory_drawer_content"
        render partial: "reports/inventory_drawer_content_frame", locals: { inventory_detail: @inventory_detail, sku: @sku }
      else
        render :inventory_detail
      end
    else
      render :inventory_detail
    end
  end

  def sku_ai_diagnosis
    @sku = Ec::Sku.find_by!(sku_code: params[:sku_code].to_s.upcase)
    @diagnosis = @sku.ai_diagnoses
      .includes(:submitted_by, events: :conversation)
      .find(params[:diagnosis_id])
    @conversation = diagnosis_conversation(@diagnosis)
    @messages = @conversation&.messages&.order(:created_at, :id)
    @diagnosis_payload = {
      type: @diagnosis[:type],
      sku: @sku.sku_code,
      analyzed_at: @diagnosis.analyzed_at,
      data: @diagnosis.data,
      events: @diagnosis.events.map do |event|
        {
          event_type: event.event_type,
          severity: event.severity,
          scope: event.scope,
          message: event.message,
          details: event.details
        }
      end
    }
  end

  def update_inventory_returns
    @sku = Ec::Sku.find_by!(sku_code: params[:sku_code].to_s.upcase)
    restockable = params[:restockable].to_s
    raise ActionController::BadRequest unless restockable.in?(%w[true false])

    item_ids = Array(params[:return_item_ids]).filter_map { |id| Integer(id, exception: false) }.uniq
    scope = Ec::SkuReturnItemsQuery.scope_for(@sku).where(id: item_ids)
    updated_count = scope.update_all(restockable: restockable == "true", updated_at: Time.current)

    @inventory_detail = Ec::InventoryPageDetailQuery.new(
      @sku,
      detail_tab: "returns",
      book_batch_page: nil,
      return_page: params[:return_page],
      return_restockable: params[:return_restockable],
      date_to: user_today,
      time_zone: user_time_zone
    ).call.merge(return_update_count: updated_count)

    render partial: "reports/inventory_drawer_content_frame",
      locals: { inventory_detail: @inventory_detail, sku: @sku }
  end

  def ozon_warehouses
    load_responsible_user_filters
    load_spu_sku_filter
    @stores = Ec::Store.active.where(platform: "ozon").where.not(ozon_raw_account_id: nil).order(:store_name)
    @store = @stores.find_by(id: params[:store_id]) || @stores.first
    @query = params[:q].to_s.strip
    @ozon_warehouse_view = params[:view].to_s.in?(%w[products clusters]) ? params[:view].to_s : "products"
    @target_days = params[:target_days].to_i
    @target_days = Ec::OzonWarehouseRecommendationQuery::DEFAULT_TARGET_DAYS unless @target_days.positive?
    @target_days = [@target_days, Ec::OzonWarehouseRecommendationQuery::MAX_TARGET_DAYS].min
    return unless @store

    @ozon_warehouse_report = Ec::OzonWarehouseRecommendationQuery.new(
      store: @store,
      from_date: user_today - 27.days,
      to_date: user_today,
      time_zone: user_time_zone,
      target_days: @target_days,
      query: @query,
      operator_id: @operator_id,
      sku_codes: warehouse_selected_sku_codes
    ).call
    current_page = ozon_warehouse_page_param
    report_rows = @ozon_warehouse_view == "clusters" ? @ozon_warehouse_report[:cluster_rows] : @ozon_warehouse_report[:rows]
    @ozon_warehouse_rows = Kaminari.paginate_array(report_rows).page(current_page).per(OZON_WAREHOUSE_PAGE_SIZE)
    if @ozon_warehouse_rows.total_pages.positive? && current_page > @ozon_warehouse_rows.total_pages
      @ozon_warehouse_rows = Kaminari.paginate_array(report_rows).page(@ozon_warehouse_rows.total_pages).per(OZON_WAREHOUSE_PAGE_SIZE)
    end
  end

  def warehouses
    all_stores = Ec::Store.active
      .where(platform: %w[ozon wb])
      .where("(platform = 'ozon' AND ozon_raw_account_id IS NOT NULL) OR (platform = 'wb' AND wb_raw_account_id IS NOT NULL)")
      .order(:platform, :store_name)
    selected_store = all_stores.find_by(id: params[:store_id]) || all_stores.first

    if selected_store&.platform == "wb"
      wb_warehouses
      template = "reports/wb_warehouses"
    else
      ozon_warehouses
      template = "reports/ozon_warehouses"
    end

    @stores = all_stores
    @store = selected_store
    @warehouse_platform = selected_store&.platform
    @unified_warehouses = true
    render template: template
  end

  def wb_warehouses
    load_responsible_user_filters
    load_spu_sku_filter
    @stores = Ec::Store.active.where(platform: "wb").where.not(wb_raw_account_id: nil).order(:store_name)
    @store = @stores.find_by(id: params[:store_id]) || @stores.first
    @query = params[:q].to_s.strip
    @wb_warehouse_view = params[:view].to_s.in?(%w[products clusters]) ? params[:view].to_s : "products"
    @target_days = params[:target_days].to_i
    @target_days = Ec::WbWarehouseRecommendationQuery::DEFAULT_TARGET_DAYS unless @target_days.positive?
    @target_days = [@target_days, Ec::WbWarehouseRecommendationQuery::MAX_TARGET_DAYS].min
    return unless @store

    @wb_warehouse_report = Ec::WbWarehouseRecommendationQuery.new(
      store: @store,
      from_date: user_today - 27.days,
      to_date: user_today,
      time_zone: user_time_zone,
      target_days: @target_days,
      query: @query,
      operator_id: @operator_id,
      sku_codes: warehouse_selected_sku_codes
    ).call
    current_page = warehouse_page_param
    report_rows = @wb_warehouse_view == "clusters" ? @wb_warehouse_report[:cluster_rows] : @wb_warehouse_report[:rows]
    @wb_warehouse_rows = Kaminari.paginate_array(report_rows).page(current_page).per(WB_WAREHOUSE_PAGE_SIZE)
    if @wb_warehouse_rows.total_pages.positive? && current_page > @wb_warehouse_rows.total_pages
      @wb_warehouse_rows = Kaminari.paginate_array(report_rows).page(@wb_warehouse_rows.total_pages).per(WB_WAREHOUSE_PAGE_SIZE)
    end
  end

  def skus
    load_ai_diagnosis_event_filter
    @skus = apply_ai_diagnosis_event_filter_to_skus(Ec::Sku.order(:sku_code))
  end

  def sku_detail
    @sku_detail_frame = request.headers["Turbo-Frame"]
    requested_tab = @sku_detail_frame&.delete_prefix("sku_detail_tab_") if @sku_detail_frame&.start_with?("sku_detail_tab_")
    @sku_detail_drawer = @sku_detail_frame == "sku_detail_drawer" || requested_tab.in?(SKU_DETAIL_AVAILABLE_TABS)
    load_sku_detail
    @sku_detail_tab_frame_id = requested_tab.in?(SKU_DETAIL_AVAILABLE_TABS) ? @sku_detail_frame : "sku_detail_tab_#{@active_tab}"

    if @sku_detail_frame == "sku_detail_drawer"
      render layout: "sku_detail_drawer"
    elsif requested_tab.in?(SKU_DETAIL_AVAILABLE_TABS)
      render partial: "reports/sku_detail_tab_frame",
             locals: { frame_id: @sku_detail_tab_frame_id, loaded: true }
    end
  end

  def sku_profit_trend
    @sku = Ec::Sku.find_by!(sku_code: params[:sku_code].to_s.upcase)
    begin
      current_monday = user_today.beginning_of_week(:monday)
      @profit_trend_weeks = SKU_PROFIT_TREND_WEEKS.times.map do |index|
        from_date = current_monday - (SKU_PROFIT_TREND_WEEKS - index).weeks
        to_date = from_date.end_of_week(:monday)
        report = WeeklyProfitReports::ReportQueryRunner.run(
          params: {
            report_type: "wsu_deep",
            from_date: from_date.iso8601,
            to_date: to_date.iso8601,
            sku_codes: [@sku.sku_code]
          },
          today: user_today
        )
        row = report[:rows].find { |item| (item[:sku] || item["sku"]).to_s == @sku.sku_code }
        { from_date:, to_date:, row: row || {} }
      end
      @profit_trend_chart_option = build_sku_profit_trend_chart_option(@profit_trend_weeks)
    rescue StandardError => error
      Rails.logger.error("SKU profit trend failed for #{params[:sku_code]}: #{error.class}: #{error.message}")
      @profit_trend_error = true
    end
    render partial: "reports/sku_profit_trend"
  end

  def sku_sales_funnel_trends
    @sku = Ec::Sku.find_by!(sku_code: params[:sku_code].to_s.upcase)
    @funnel_trend_to_date = parse_report_date(params[:trend_to_date]) || user_today
    @funnel_trend_from_date = parse_report_date(params[:trend_from_date]) || (@funnel_trend_to_date - 27.days)
    if @funnel_trend_to_date < @funnel_trend_from_date || (@funnel_trend_to_date - @funnel_trend_from_date).to_i >= SKU_SALES_FUNNEL_TREND_MAX_DAYS
      raise ArgumentError, "invalid_date_range"
    end

    @funnel_store_trends = SalesFunnelReports::SkuDailyTrendQuery.new(
      sku: @sku,
      from_date: @funnel_trend_from_date,
      to_date: @funnel_trend_to_date
    ).call
    @funnel_store_trends.each do |trend|
      trend[:chart_option] = build_sku_sales_funnel_trend_chart_option(trend)
    end
  rescue ArgumentError => error
    Rails.logger.info("SKU sales funnel trend rejected for #{params[:sku_code]}: #{error.message}")
    @funnel_trend_error = true
  rescue StandardError => error
    Rails.logger.error("SKU sales funnel trend failed for #{params[:sku_code]}: #{error.class}: #{error.message}")
    @funnel_trend_error = true
  ensure
    render partial: "reports/sku_sales_funnel_trends" unless performed?
  end

  def new_sku_predicted_cost
    @sku = Ec::Sku.find_by!(sku_code: params[:sku_code].to_s.upcase)
    @predicted_cost = @sku.predicted_costs.new(cost_currency: "CNY", effective_from: user_today)
    render :new_sku_predicted_cost_modal
  end

  def create_sku_predicted_cost
    @sku = Ec::Sku.find_by!(sku_code: params[:sku_code].to_s.upcase)
    predicted_cost = @sku.predicted_costs.new(sku_predicted_cost_params)

    if predicted_cost.save
      redirect_to report_sku_path(@sku.sku_code, tab: "costs")
    else
      @predicted_cost = predicted_cost
      render :new_sku_predicted_cost_modal, status: :unprocessable_entity
    end
  end

  def create_sku_attachment
    @sku = Ec::Sku.find_by!(sku_code: params[:sku_code].to_s.upcase)
    uploaded_files = sku_attachment_files_param
    attach_type = sku_attachment_type_param

    if uploaded_files.empty? || !Ec::Attachment::SKU_ATTACH_TYPES.include?(attach_type)
      redirect_to sku_attachments_tab_path(@sku), alert: t("reports.sku_detail.attachments.upload_failed")
      return
    end

    attachments = []
    blobs = []
    Ec::Attachment.transaction do
      uploaded_files.each do |uploaded_file|
        attachment = build_sku_attachment(uploaded_file, attach_type)
        attachment.save!
        blobs << attachment.attach_file!(io: uploaded_file.tempfile, content_type: uploaded_file.content_type)
        @sku.attachment_links.create!(ec_attachment: attachment)
        attachments << attachment
      end
    end

    redirect_to sku_attachments_tab_path(@sku), notice: t("reports.sku_detail.attachments.uploaded", count: attachments.size)
  rescue ActiveRecord::RecordInvalid, ActiveStorage::IntegrityError
    blobs.to_a.each(&:purge)
    attachments.to_a.each(&:destroy)
    redirect_to sku_attachments_tab_path(@sku), alert: t("reports.sku_detail.attachments.upload_failed")
  end

  def edit_sku_attachment
    @sku = Ec::Sku.find_by!(sku_code: params[:sku_code].to_s.upcase)
    attachment = sku_attachment_for(@sku)
    raise ActionController::BadRequest, "Unsupported inline field" unless params[:inline_field] == "attach_type"

    render partial: "shared/inline_edit_cell",
      locals: view_context.attachment_type_inline_cell_locals(
        attachment,
        options: sku_attachment_type_options,
        update_path: report_sku_attachment_path(@sku.sku_code, attachment, locale: params[:locale]),
        edit_path: edit_report_sku_attachment_path(@sku.sku_code, attachment, locale: params[:locale]),
        dom_id_prefix: sku_attachment_dom_id_prefix,
        editing: true
      )
  end

  def update_sku_attachment
    @sku = Ec::Sku.find_by!(sku_code: params[:sku_code].to_s.upcase)
    attachment = sku_attachment_for(@sku)
    raise ActionController::BadRequest, "Unsupported update request" unless inline_edit_request?

    field = inline_field_name(%w[attach_type])
    attach_type = params.require(:ec_attachment).permit(:attach_type)[:attach_type]
    raise ActionController::BadRequest, "Unsupported attachment type" unless attach_type.in?(Ec::Attachment::SKU_ATTACH_TYPES)

    locals = ->(editing) do
      view_context.attachment_type_inline_cell_locals(
        attachment,
        options: sku_attachment_type_options,
        update_path: report_sku_attachment_path(@sku.sku_code, attachment, locale: params[:locale]),
        edit_path: edit_report_sku_attachment_path(@sku.sku_code, attachment, locale: params[:locale]),
        dom_id_prefix: sku_attachment_dom_id_prefix,
        editing: editing
      )
    end

    if attachment.update(field => attach_type)
      render_inline_edit_success(
        frame_id: view_context.attachment_type_inline_frame_id(attachment, dom_id_prefix: sku_attachment_dom_id_prefix),
        feedback_target: "global_toast",
        cell_partial: "shared/inline_edit_cell",
        cell_locals: locals.call(false),
        message: t("erp.inline_edit.messages.saved")
      )
    else
      render_inline_edit_failure(
        frame_id: view_context.attachment_type_inline_frame_id(attachment, dom_id_prefix: sku_attachment_dom_id_prefix),
        feedback_target: "global_toast",
        cell_partial: "shared/inline_edit_cell",
        cell_locals: locals.call(true),
        message: t("erp.inline_edit.messages.save_failed")
      )
    end
  end

  def new_sku_operation_action
    @sku = Ec::Sku.find_by!(sku_code: params[:sku_code].to_s.upcase)
    @operation_action = Ec::OperationAction.new(diff_result: { "note" => "" })
    render :new_sku_operation_action_modal
  end

  def create_sku_operation_action
    @sku = Ec::Sku.find_by!(sku_code: params[:sku_code].to_s.upcase)
    sku_product = @sku.sku_products.includes(:store).order(:id).first
    note = operation_action_note_param

    if sku_product.blank?
      redirect_to report_sku_path(@sku.sku_code, tab: "ai_inventory_health", locale: params[:locale].presence), alert: t("reports.sku_detail.operation_record.no_product")
      return
    end

    if note.blank?
      redirect_to report_sku_path(@sku.sku_code, tab: "ai_inventory_health", locale: params[:locale].presence), alert: t("reports.sku_detail.operation_record.note_required")
      return
    end

    Ec::OperationAction.create!(
      operation_type: "manual_note",
      operated_by_user: current_user,
      operated_at: Time.current,
      sku_product: sku_product,
      sku: @sku,
      store: sku_product.store,
      diff_result: { "note" => note },
      record_by_system: false
    )

    redirect_to report_sku_path(@sku.sku_code, tab: "ai_inventory_health", locale: params[:locale].presence), notice: t("reports.sku_detail.operation_record.created")
  end

  def edit_sku_operation_action
    load_manual_sku_operation_action
    render :edit_sku_operation_action_modal
  end

  def update_sku_operation_action
    load_manual_sku_operation_action
    note = operation_action_note_param

    if note.blank?
      redirect_to report_sku_path(@sku.sku_code, tab: "ai_inventory_health", locale: params[:locale].presence), alert: t("reports.sku_detail.operation_record.note_required")
      return
    end

    @operation_action.update!(diff_result: { "note" => note })
    redirect_to report_sku_path(@sku.sku_code, tab: "ai_inventory_health", locale: params[:locale].presence), notice: t("reports.sku_detail.operation_record.updated")
  end

  def destroy_sku_operation_action
    load_manual_sku_operation_action
    @operation_action.destroy!

    redirect_to report_sku_path(@sku.sku_code, tab: "ai_inventory_health", locale: params[:locale].presence),
                notice: t("reports.sku_detail.operation_record.deleted"),
                status: :see_other
  end

  def download_sku_attachment
    @sku = Ec::Sku.find_by!(sku_code: params[:sku_code].to_s.upcase)
    attachment = sku_attachment_for(@sku)

    if attachment.file.service.is_a?(ActiveStorage::Service::QiniuService)
      redirect_to qiniu_attachment_download_url(attachment), allow_other_host: true
      return
    end

    send_data attachment.file.download,
              filename: attachment.filename,
              type: attachment.file.content_type || "application/octet-stream",
              disposition: "attachment"
  end

  def preview_sku_attachment
    @sku = Ec::Sku.find_by!(sku_code: params[:sku_code].to_s.upcase)
    attachment = sku_attachment_for(@sku)

    if view_context.attachment_office_previewable?(attachment)
      source_url = attachment.file.url(disposition: :inline, filename: attachment.filename)
      redirect_to "https://view.officeapps.live.com/op/embed.aspx?src=#{CGI.escape(source_url)}", allow_other_host: true
    elsif view_context.attachment_browser_previewable?(attachment)
      if attachment.file.service.is_a?(ActiveStorage::Service::QiniuService)
        redirect_to attachment.file.url(disposition: :inline, filename: attachment.filename), allow_other_host: true
      else
        send_data attachment.file.download,
                  filename: attachment.filename,
                  type: view_context.attachment_browser_preview_content_type(attachment),
                  disposition: "inline"
      end
    else
      head :unprocessable_entity
    end
  end

  def destroy_sku_attachment
    @sku = Ec::Sku.find_by!(sku_code: params[:sku_code].to_s.upcase)
    attachment = sku_attachment_for(@sku)
    link = @sku.attachment_links.find_by!(ec_attachment: attachment)

    link.destroy!
    if attachment.attachment_links.reload.none?
      attachment.file.purge if attachment.file.attached?
      attachment.destroy!
    end

    redirect_to sku_attachments_tab_path(@sku), notice: t("reports.sku_detail.attachments.deleted")
  end

  def destroy_sku_inventory_health_result
    @sku = Ec::Sku.find_by!(sku_code: params[:sku_code].to_s.upcase)
    @sku.inventory_health_results.find(params[:result_id]).destroy!

    redirect_to report_sku_path(
      @sku.sku_code,
      tab: "ai_inventory_health",
      locale: params[:locale].presence
    ), notice: t("reports.sku_detail.ai_inventory_health.deleted"), status: :see_other
  end

  def costs
    load_master_sku_category_filter
    load_responsible_user_filters
    load_ai_diagnosis_event_filter

    sku_costs_scope = Ec::SkuCost.latest_as_of(user_today).includes(:sku, :sku_dimension)
    wb_costs_scope = Ec::SkuPlatformCost.includes(:sku, cost: :sku_dimension).where(platform: "wb").order(:sku_code, :delivery_mode, :company_type)
    ozon_costs_scope = Ec::SkuPlatformCost.includes(:sku, cost: :sku_dimension).where(platform: "ozon").order(:sku_code, :delivery_mode, :company_type)

    @sku_costs = apply_ai_diagnosis_event_filter_to_sku_records(apply_responsible_user_filters_to_sku_records(apply_master_sku_category_filter_to_sku_records(sku_costs_scope)))
    @wb_costs = apply_ai_diagnosis_event_filter_to_sku_records(apply_responsible_user_filters_to_sku_records(apply_master_sku_category_filter_to_sku_records(wb_costs_scope)))
    @ozon_costs = apply_ai_diagnosis_event_filter_to_sku_records(apply_responsible_user_filters_to_sku_records(apply_master_sku_category_filter_to_sku_records(ozon_costs_scope)))
  end

  def sku_sales
    @period = params[:period].presence_in(%w[day week month]) || "day"
    @grain = params[:grain].presence_in(%w[store platform sku]) || "store"
    @from_date = parse_report_date(params[:from_date]) || (user_today - 30.days)
    @to_date = parse_report_date(params[:to_date]) || user_today
    @stores = Ec::Store.order(:platform, :store_name)
    @skus = Ec::Sku.order(:sku_code)
    @selected_sku_codes = selected_sku_codes
    @selected_platform = params[:platform].presence_in(Ec::Order::PLATFORMS.values)
    @selected_store_id = params[:store_id].presence
    @sku_sales_rows = build_sku_sales_rows
    @sku_sales_summary = build_sku_sales_summary(@sku_sales_rows)
    @sku_sales_chart_series = build_sku_sales_chart_series(@sku_sales_rows)
    @sku_sales_chart_option = build_sku_sales_chart_option(@sku_sales_chart_series)
  end

  private

  def build_sku_profit_trend_chart_option(weeks)
    labels = weeks.map { |week| "#{week[:from_date].strftime('%m-%d')} ~ #{week[:to_date].strftime('%m-%d')}" }
    metric_options = {
      net_sales: { axis: 0, color: "#176b87" },
      revenue: { axis: 1, color: "#167044" },
      ads: { axis: 1, color: "#b42318" },
      goods_cost: { axis: 1, color: "#a15c07" },
      average_profit_per_order: { axis: 1, color: "#0f766e" },
      annualized_return_pct: { axis: 2, color: "#7c3aed" },
      annualized_net_profit_cny: { axis: 1, color: "#475569" }
    }
    series = SKU_PROFIT_TREND_METRICS.map do |metric|
      settings = metric_options.fetch(metric)
      {
        name: t("reports.sku_detail.profit_trend.metrics.#{metric}"),
        type: "line",
        smooth: true,
        symbolSize: 7,
        yAxisIndex: settings[:axis],
        itemStyle: { color: settings[:color] },
        lineStyle: { color: settings[:color], width: 2 },
        data: weeks.map { |week| profit_trend_value(week[:row], metric) }
      }
    end

    {
      tooltip: { trigger: "axis" },
      legend: { type: "scroll", top: 0, data: series.map { |item| item[:name] } },
      grid: { left: 48, right: 82, top: 64, bottom: 42, containLabel: true },
      xAxis: { type: "category", boundaryGap: false, data: labels },
      yAxis: [
        { type: "value", name: t("reports.sku_detail.profit_trend.axes.quantity"), minInterval: 1 },
        { type: "value", name: t("reports.sku_detail.profit_trend.axes.amount") },
        { type: "value", name: "%", position: "right", offset: 54 }
      ],
      series:
    }
  end

  def build_sku_sales_funnel_trend_chart_option(trend)
    amount_metrics = %i[orders_sum buyouts_sum revenue]
    percent_metrics = %i[conv_to_cart cart_to_order buyout_percent conv_tocart]
    rank_metric = :position_category
    has_rank = rank_metric.in?(trend[:metrics])
    labels = trend[:rows].map { |row| row[:date] }
    series = trend[:metrics].map do |metric|
      selected = metric.in?(trend[:default_metrics])
      {
        name: t("sales_funnel_reports.columns.#{trend[:platform]}.#{metric}"),
        type: "line",
        smooth: true,
        showSymbol: false,
        yAxisIndex: if metric == rank_metric
          3
        elsif amount_metrics.include?(metric)
          1
        elsif percent_metrics.include?(metric)
          2
        else
          0
        end,
        data: trend[:rows].map { |row| row.dig(:values, metric) },
        selected:
      }
    end
    {
      tooltip: { trigger: "axis" },
      legend: {
        type: "scroll",
        top: 0,
        selected: series.to_h { |item| [item[:name], item.delete(:selected)] }
      },
      grid: { left: 38, right: has_rank ? 108 : 62, top: 62, bottom: 42, containLabel: true },
      xAxis: { type: "category", boundaryGap: false, data: labels },
      yAxis: [
        { type: "value", name: t("reports.sku_detail.funnel_trends.axes.count"), minInterval: 1 },
        { type: "value", name: t("reports.sku_detail.funnel_trends.axes.amount") },
        { type: "value", name: "%", position: "right", offset: 42 }
      ] + (has_rank ? [{
        type: "value",
        name: t("sales_funnel_reports.columns.ozon.position_category"),
        position: "right",
        offset: 84,
        inverse: true,
        min: 1
      }] : []),
      series:
    }
  end

  def profit_trend_value(row, metric)
    value = row[metric] || row[metric.to_s]
    value.nil? ? nil : value.to_f
  end

  def load_sku_detail(active_tab: nil)
    @sku = Ec::Sku.includes(
      { master_sku: { ec_category: :parent } },
      :sku_category,
      { cost: :sku_dimension },
      :platform_costs,
      :store_assignments,
      :inventory_levels,
      :current_marketing_state,
      :sku_products,
      :predicted_costs,
      attachments: { file_attachment: :blob }
    ).find_by!(sku_code: params[:sku_code].to_s.upcase)
    @active_tab = active_tab || params[:tab].presence_in(SKU_DETAIL_AVAILABLE_TABS) || "sales_funnel"
    @active_tab = "sales_funnel" if @active_tab == "operation"
    @stores = Ec::Store.order(:platform, :store_name)
    @sku_cost = @sku.cost
    @wb_costs = @sku.platform_costs.select { |cost| cost.platform == "wb" }.sort_by { |cost| [cost.delivery_mode.to_s, cost.company_type.to_s] }
    @ozon_costs = @sku.platform_costs.select { |cost| cost.platform == "ozon" }.sort_by { |cost| [cost.delivery_mode.to_s, cost.company_type.to_s] }
    @store_assignments = @sku.store_assignments.sort_by { |assignment| [assignment.platform.to_s, assignment.store_key.to_s] }
    @sku_products = @sku.sku_products.includes(:store).sort_by { |product| [product.platform.to_s, product.store.store_name.to_s, product.product_id.to_s] }
    @predicted_costs = @sku.predicted_costs.sort_by { |cost| [cost.effective_from || Date.new(1900, 1, 1), cost.id || 0] }.reverse
    @attachments = @sku.attachments.sort_by { |attachment| [attachment.created_at || Time.zone.at(0), attachment.id || 0] }.reverse
    if @active_tab == "ai_inventory_health"
      @inventory_health_results = @sku.ai_diagnoses
        .where(type: [ Ec::RestockingDiagnosis.sti_name, Ec::OperationActionDiagnosis.sti_name, Ec::GradeInspect.sti_name ])
        .includes(:submitted_by, events: :conversation)
        .recent_first
        .limit(3)
      @operation_actions = @sku.operation_actions
        .where(operation_type: "manual_note", record_by_system: false)
        .includes(:operated_by_user, :sku_product, :store)
        .order(operated_at: :desc, id: :desc)
        .limit(7)
      @inventory_health_timeline = build_inventory_health_timeline
    end
    @predicted_cost ||= @sku.predicted_costs.new(cost_currency: "CNY", effective_from: user_today)

    @operator_metrics = Ec::OperatorSkuMetricsQuery.new(
      skus: [@sku],
      date_to: user_today,
      time_zone: user_time_zone
    ).performance_metrics.fetch(@sku)
    load_sku_operation_overview if @active_tab.in?(%w[sales_funnel profit])
    load_sku_supply_orders if @active_tab == "supply_orders"
    load_sku_warehouses if @active_tab == "warehouses"
    load_sku_operation_actions if @active_tab == "operation_actions"
    load_sku_inventory_detail if @active_tab == "inventory"
    load_sku_ads if @active_tab == "ads"

    @from_date = parse_report_date(params[:from_date]) || default_sku_detail_from_date
    @to_date = parse_report_date(params[:to_date]) || user_today
    @period = params[:period].presence_in(%w[day week month]) || "day"
    @grain = params[:grain].presence_in(%w[store platform sku]) || "store"
    @selected_platform = params[:platform].presence_in(Ec::Order::PLATFORMS.values)
    @selected_store_id = params[:store_id].presence
    load_sku_search_terms if @active_tab == "search_terms"

    @sku_sales_rows = sku_detail_sales_rows(
      sku_products: @sku_products,
      from_date: @from_date,
      to_date: @to_date,
      period: sku_detail_sales_period,
      grain: @grain,
      platform: @selected_platform,
      store_id: @selected_store_id
    )
    @sku_sales_summary = build_sku_sales_summary(@sku_sales_rows)
    @sku_sales_chart_series = build_sku_sales_chart_series(@sku_sales_rows)
    @sku_sales_chart_option = build_sku_sales_chart_option(@sku_sales_chart_series)
  end

  def sku_predicted_cost_params
    params.require(:ec_sku_predicted_cost).permit(:cost_money, :cost_currency, :effective_from, :effective_to, :note)
  end

  def load_manual_sku_operation_action
    @sku = Ec::Sku.find_by!(sku_code: params[:sku_code].to_s.upcase)
    @operation_action = @sku.operation_actions
      .where(operation_type: "manual_note", record_by_system: false)
      .find(params[:action_id])
  end

  def operation_action_note_param
    (params.dig(:ec_operation_action, :note).presence || params[:note]).to_s.strip
  end

  def build_inventory_health_timeline
    diagnosis_entries = @inventory_health_results.map do |result|
      { type: :diagnosis, record: result, occurred_at: result.created_at, id: result.id }
    end
    operation_entries = @operation_actions.map do |action|
      { type: :operation, record: action, occurred_at: action.operated_at, id: action.id }
    end

    (diagnosis_entries + operation_entries).sort_by do |entry|
      [-entry[:occurred_at].to_f, -entry[:id].to_i]
    end
  end

  def diagnosis_conversation(diagnosis)
    linked_conversation = diagnosis.events.filter_map(&:conversation).first
    return linked_conversation if linked_conversation
    return unless diagnosis.is_a?(Ec::GradeInspect)

    Conversation
      .joins(:agent, :messages)
      .where(
        agents: { code: AITasks::SkuGradeInspector::AGENT_CODE },
        module_name: "sku_grade_inspections",
        business_object_type: "Ec::Sku",
        business_object_id: diagnosis.sku_id.to_s,
        created_at: (diagnosis.created_at - 1.hour)..(diagnosis.created_at + 5.minutes)
      )
      .where(
        "messages.content LIKE :json_id OR messages.content LIKE :text_id",
        json_id: "%\"id\":#{diagnosis.id}%",
        text_id: "%id=#{diagnosis.id}%"
      )
      .order(created_at: :desc, id: :desc)
      .first
  end

  def sku_attachment_files_param
    Array(params.dig(:ec_attachment, :files)).compact_blank
  end

  def sku_attachment_type_param
    params.dig(:ec_attachment, :attach_type).to_s
  end

  def sku_attachment_type_options
    Ec::Attachment::SKU_ATTACH_TYPES.map do |type|
      [I18n.t("reports.sku_detail.attachments.attach_types.#{type}"), type]
    end
  end

  def sku_attachment_dom_id_prefix
    "sku-#{@sku.id}-attachments"
  end

  def build_sku_attachment(uploaded_file, attach_type)
    filename = File.basename(uploaded_file.original_filename.to_s)
    filename = "attachment" if filename.blank? || filename == "."
    Ec::Attachment.new(
      attach_type: attach_type,
      filename: filename,
      qiniu_hash: uploaded_file_digest(uploaded_file),
      oss_path: sku_attachment_oss_path(filename)
    )
  end

  def uploaded_file_digest(uploaded_file)
    uploaded_file.rewind
    Digest::SHA256.hexdigest(uploaded_file.read)
  ensure
    uploaded_file.rewind if uploaded_file.respond_to?(:rewind)
  end

  def sku_attachment_oss_path(filename)
    safe_filename = filename.to_s.gsub(/[^\w.\-]+/, "_")
    safe_filename = "attachment" if safe_filename.blank?
    "ec/skus/#{@sku.id}/attachments/#{SecureRandom.uuid}/#{safe_filename}"
  end

  def sku_attachment_for(sku)
    sku.attachments.with_attached_file.find(params[:attachment_id])
  end

  def qiniu_attachment_download_url(attachment)
    service = attachment.file.service
    key = attachment.file.blob.key
    fop = "attname=#{URI::DEFAULT_PARSER.escape(attachment.filename)}"

    if service.bucket_private
      Qiniu::Auth.authorize_download_url_2(
        service.domain,
        key,
        schema: service.protocol,
        fop: fop,
        expires_in: ActiveStorage.service_urls_expire_in
      )
    else
      "#{service.protocol}://#{service.domain}/#{CGI.escape(key)}?#{fop}"
    end
  end

  def sku_attachments_tab_path(sku)
    report_sku_path(sku.sku_code, request.query_parameters.merge(tab: "basic").except(:sku_code, :attachment_id))
  end

  def build_inventory_rows(scope)
    current_page = inventory_page_param
    skus = scope.page(current_page).per(10)
    if skus.total_pages.positive? && current_page > skus.total_pages
      skus = scope.page(skus.total_pages).per(10)
    end
    metrics_by_sku = Ec::InventoryVelocityMetricsQuery.new(
      sku_codes: skus.map(&:sku_code),
      date_to: user_today,
      time_zone: user_time_zone
    ).call
    event_types_by_sku_id = load_latest_red_ai_diagnosis_event_types_for(skus)

    rows = skus.map do |sku|
      fetch_inventory_row(sku, metrics: metrics_by_sku[sku.sku_code] || {}).merge(
        ai_diagnosis_event_types: event_types_by_sku_id.fetch(sku.id, [])
      )
    end

    Kaminari.paginate_array(
      rows,
      total_count: skus.total_count,
      limit: skus.limit_value,
      offset: skus.offset_value
    )
  end

  def build_inventory_volume_summary(scope)
    rows = scope.map do |sku|
      fetch_inventory_row(sku)
    end

    Ec::InventoryVolumeSummaryBuilder.call(rows)
  end

  def inventory_page_param
    requested_page = params[:jump_page].presence || params[:page].presence
    current_page = params[:current_page].presence || params[:page].presence

    page = requested_page.to_i if requested_page.to_s.match?(/\A\d+\z/)
    page ||= current_page.to_i if current_page.to_s.match?(/\A\d+\z/)
    page = 1 if page.to_i <= 0
    page
  end

  def ozon_warehouse_page_param
    warehouse_page_param
  end

  def warehouse_page_param
    requested_page = params[:jump_page].presence || params[:page].presence
    current_page = params[:current_page].presence || params[:page].presence

    page = requested_page.to_i if requested_page.to_s.match?(/\A\d+\z/)
    page ||= current_page.to_i if current_page.to_s.match?(/\A\d+\z/)
    page = 1 if page.to_i <= 0
    page
  end

  def warehouse_report_path(query_params = {})
    return sku_detail_tab_path("warehouses", query_params) if @sku_warehouse_embed
    return reports_warehouses_path(query_params) if @unified_warehouses
    return reports_wb_warehouses_path(query_params) if @store&.platform == "wb"

    reports_ozon_warehouses_path(query_params)
  end

  def warehouse_selected_sku_codes
    return nil unless spu_sku_filter_active?

    apply_spu_sku_filter_to_skus(Ec::Sku.all).pluck(:sku_code)
  end

  def inventory_skus_scope
    scope = Ec::Sku.includes({ cost: :sku_dimension }, :current_marketing_state)
    scope = apply_master_sku_category_filter_to_skus(scope)
    scope = apply_spu_sku_filter_to_skus(scope)
    scope = apply_marketing_state_filters(scope)
    scope = apply_responsible_user_filters_to_skus(scope)
    scope = apply_ai_diagnosis_event_filter_to_skus(scope)
    return scope if @sku_query.blank?

    scope.where("LOWER(ec_skus.sku_code) LIKE ?", inventory_sku_filter_pattern)
  end

  def apply_inventory_turnover_filter(scope)
    return scope unless inventory_turnover_filter_active?

    sku_codes = scope.pluck(:sku_code)
    return scope.none if sku_codes.empty?

    metrics_by_sku = Ec::InventoryTurnoverMetricsQuery.new(
      sku_codes: sku_codes,
      date_to: user_today,
      time_zone: user_time_zone
    ).call

    matching_sku_codes = sku_codes.select do |sku_code|
      inventory_turnover_matches_all?(
        turnover_days: metrics_by_sku.dig(sku_code, :turnover_days),
        turnover_days_with_procurement: metrics_by_sku.dig(sku_code, :turnover_days_with_procurement)
      )
    end

    scope.where(sku_code: matching_sku_codes)
  end

  def inventory_sku_filter_pattern
    "%#{ActiveRecord::Base.sanitize_sql_like(@sku_query.downcase)}%"
  end

  def inventory_turnover_filter_active?
    @turnover_days_min.present? || @turnover_days_max.present? ||
      @procurement_turnover_days_min.present? || @procurement_turnover_days_max.present?
  end

  def inventory_filters_active?
    @sku_query.present? || inventory_turnover_filter_active? || responsible_user_filters_active? || spu_sku_filter_active? || sku_marketing_state_filters_active? || master_sku_category_filter_active? || ai_diagnosis_event_filter_active?
  end

  def inventory_turnover_matches_all?(turnover_days:, turnover_days_with_procurement:)
    inventory_turnover_range_matches?(
      value: turnover_days,
      min_value: @turnover_days_min,
      max_value: @turnover_days_max
    ) && inventory_turnover_range_matches?(
      value: turnover_days_with_procurement,
      min_value: @procurement_turnover_days_min,
      max_value: @procurement_turnover_days_max
    )
  end

  def inventory_turnover_range_matches?(value:, min_value:, max_value:)
    return true if min_value.blank? && max_value.blank?
    return false if value.blank?
    return false if value.negative? && !min_value&.negative?

    min_matches = min_value.nil? || value >= min_value
    max_matches = max_value.nil? || value <= max_value

    min_matches && max_matches
  end

  def fetch_inventory_row(sku, metrics: {})
    raw_row = Ec::InventoryPageRowQuery.new(sku).call

    Ec::InventoryReportRowMetricsBuilder.call(
      raw_row,
      metrics: metrics,
      cache_updated_at: Time.current
    )
  end

  def load_sku_inventory_detail
    @inventory_detail = Ec::InventoryPageDetailQuery.new(
      @sku,
      detail_tab: params[:detail_tab],
      book_batch_page: params[:book_batch_page],
      return_page: params[:return_page],
      return_restockable: params[:return_restockable],
      date_to: user_today,
      time_zone: user_time_zone
    ).call
  end

  def load_sku_ads
    @ads_platform = params[:ads_platform].presence_in(%w[ozon wb]) || "ozon"
    monday = user_today.beginning_of_week(:monday)
    @ads_from_date = parse_report_date(params[:ads_from_date]) || monday - 1.week
    @ads_to_date = parse_report_date(params[:ads_to_date]) || monday - 1.day
    @ads_from_date, @ads_to_date = @ads_to_date, @ads_from_date if @ads_from_date > @ads_to_date
    period_days = (@ads_to_date - @ads_from_date).to_i + 1
    @ads_previous_to_date = @ads_from_date - 1.day
    @ads_previous_from_date = @ads_previous_to_date - (period_days - 1).days

    if @ads_platform == "ozon"
      load_sku_ozon_ads
    else
      load_sku_wb_ads
    end
  end

  def load_sku_ozon_ads
    @ads_stores = Ec::Store.where(platform: "ozon", is_active: true).where.not(ozon_raw_account_id: nil).order(:store_name)
    @ads_store = @ads_stores.find_by(id: params[:ads_store_id]) || @ads_stores.first
    return unless @ads_store

    product_ids = @sku.sku_products.select { |product| product.store_id == @ads_store.id && product.platform == "ozon" }
      .filter_map { |product| product.platform_sku_id.to_s.presence }.to_set
    analytics = RawOzon::Ads::AnalyticsQuery.new(account: @ads_store.raw_ozon_account, store: @ads_store, from_date: @ads_from_date, to_date: @ads_to_date)
    previous = RawOzon::Ads::AnalyticsQuery.new(account: @ads_store.raw_ozon_account, store: @ads_store, from_date: @ads_previous_from_date, to_date: @ads_previous_to_date)

    @ads_ozon_cpc_rows = analytics.cpc_rows(states: %w[CAMPAIGN_STATE_RUNNING CAMPAIGN_STATE_INACTIVE]).select do |row|
      row[:unit].products.any? { |product| product.is_current? && product_ids.include?(product.ozon_sku_id.to_s) }
    end
    previous_cpc = previous.cpc_rows(states: %w[CAMPAIGN_STATE_RUNNING CAMPAIGN_STATE_INACTIVE]).select do |row|
      row[:unit].products.any? { |product| product.is_current? && product_ids.include?(product.ozon_sku_id.to_s) }
    end
    _unit, @ads_ozon_cpo_rows = analytics.cpo_selected_rows
    _previous_unit, previous_cpo = previous.cpo_selected_rows
    @ads_ozon_cpo_rows.select! { |row| row[:sku]&.id == @sku.id }
    previous_cpo.select! { |row| row[:sku]&.id == @sku.id }
    builder = RawOzon::Ads::ComparisonBuilder.new
    @ads_ozon_cpc_comparisons = builder.rows(@ads_ozon_cpc_rows, previous_cpc,
      key_builder: ->(row) { row[:unit].external_id }, metrics: %i[spend ad_revenue orders_count impressions clicks cart_additions ctr avg_cpc])
    @ads_ozon_cpo_comparisons = builder.rows(@ads_ozon_cpo_rows, previous_cpo,
      key_builder: ->(row) { row[:product].ozon_sku_id }, metrics: %i[spend ad_revenue orders_count drr])
  end

  def load_sku_wb_ads
    @ads_stores = Ec::Store.active.where(platform: "wb").where.not(wb_api_token: [nil, ""]).order(:store_name)
    @ads_store = @ads_stores.find_by(id: params[:ads_store_id]) || @ads_stores.first
    return unless @ads_store

    analytics = RawWb::Adv::AnalyticsQuery.new(store: @ads_store, from_date: @ads_from_date, to_date: @ads_to_date)
    previous = RawWb::Adv::AnalyticsQuery.new(store: @ads_store, from_date: @ads_previous_from_date, to_date: @ads_previous_to_date)
    @ads_wb_rows = analytics.product_rows.select { |row| row[:sku_product]&.sku_code == @sku.sku_code }
    previous_rows = previous.product_rows.select { |row| row[:sku_product]&.sku_code == @sku.sku_code }
    @ads_wb_comparisons = RawWb::Adv::ComparisonBuilder.new.rows(
      @ads_wb_rows, previous_rows, key_builder: ->(row) { row[:nm_id] }, metrics: Reports::WbAdsController::ROW_METRICS
    )
  end

  def sku_ads_metric(value, type: :number, precision: 2)
    return t("common.empty_value") if value.nil?

    case type
    when :currency then helpers.number_to_currency(value, unit: "₽", format: "%n %u", precision: precision)
    when :percentage then helpers.number_to_percentage(value, precision: precision)
    when :decimal then helpers.number_with_precision(value, precision: precision, strip_insignificant_zeros: true)
    else helpers.number_with_delimiter(value.to_i)
    end
  end

  def sku_ads_comparison_label(comparison)
    delta = comparison&.dig(:delta_pct)
    return t("reports.ozon_ads.comparison.unavailable") if delta.nil?

    arrow = comparison[:trend] == "up" ? "↗" : (comparison[:trend] == "down" ? "↘" : "→")
    "#{arrow} #{format('%.2f', delta)}%"
  end

  def sku_ads_comparison_class(comparison)
    semantic = comparison&.dig(:semantic)
    semantic.in?(%w[positive negative neutral]) ? "is-#{semantic}" : "is-none"
  end

  def load_sku_operation_overview
    @operation_store_options = WeeklyProfitReports::ReportQueryRunner.store_options
    if @active_tab == "sales_funnel"
      @funnel_to_date = parse_report_date(params[:funnel_to_date]) || user_today
      @funnel_from_date = parse_report_date(params[:funnel_from_date]) || (@funnel_to_date - 13.days)
      @funnel_store_ref = operation_store_ref(params[:funnel_store_ref])
      begin
        @operation_funnel_report = SalesFunnelReports::SkuDailyReportQueryRunner.run(
          params: {
            from_date: @funnel_from_date.iso8601,
            to_date: @funnel_to_date.iso8601,
            store_ref: @funnel_store_ref,
            sku_codes: [@sku.sku_code]
          },
          today: user_today
        )
      rescue ActiveRecord::RecordNotFound, ActionController::ParameterMissing, ArgumentError => error
        @operation_funnel_error = error.message
      end
    else
      last_monday = user_today.beginning_of_week(:monday) - 1.week
      @profit_from_date = parse_report_date(params[:profit_from_date]) || last_monday
      @profit_to_date = parse_report_date(params[:profit_to_date]) || last_monday.end_of_week(:monday)
      @profit_report_type = params[:profit_report_type].presence_in(WeeklyProfitReports::ReportQueryRunner::REPORT_TYPES) || "wr"
      @profit_store_ref = operation_store_ref(params[:profit_store_ref])

      begin
        profit_params = {
          report_type: @profit_report_type,
          from_date: @profit_from_date.iso8601,
          to_date: @profit_to_date.iso8601,
          sku_codes: [@sku.sku_code]
        }
        profit_params[:store_ref] = @profit_store_ref if @profit_report_type == "wr"
        @operation_profit_report = WeeklyProfitReports::ReportQueryRunner.run(
          params: profit_params,
          today: user_today
        )
      rescue ActiveRecord::RecordNotFound, ActionController::ParameterMissing, ArgumentError => error
        @operation_profit_error = error.message
      end
    end
  end

  def operation_store_ref(requested_store)
    requested_store = requested_store.presence
    return requested_store if @operation_store_options.any? { |store| store[:ref] == requested_store }

    @operation_store_options.first&.dig(:ref)
  end

  def load_sku_supply_orders
    available_refs = @sku_products.filter_map do |product|
      store = product.store
      account_id = store.platform == "wb" ? store.wb_raw_account_id : store.ozon_raw_account_id
      "#{store.platform}:#{account_id}" if account_id.present?
    end.uniq
    @sku_supply_store_options = SupplyOrderReports::ReportQuery.store_options.select { |store| store[:ref].in?(available_refs) }
    @sku_supply_store_ref = params[:supply_store_ref].presence_in(@sku_supply_store_options.map { |store| store[:ref] }) || @sku_supply_store_options.first&.dig(:ref)
    return if @sku_supply_store_ref.blank?

    @sku_supply_platform = @sku_supply_store_ref.split(":", 2).first
    @sku_supply_selected_statuses = SupplyOrderReports::ReportQuery.new(params: params).selected_statuses(@sku_supply_platform)
    query_params = request.query_parameters.merge(
      store_ref: @sku_supply_store_ref,
      sku_codes: [@sku.sku_code],
      page: params[:jump_page].presence || params[:supply_page]
    )
    @sku_supply_report = SupplyOrderReports::ReportQuery.new(params: query_params).call
  rescue ActiveRecord::RecordNotFound, ActionController::ParameterMissing, ArgumentError => error
    @sku_supply_error = error.message
  end

  def load_sku_operation_actions
    @sku_operation_action_type = params[:operation_action_type].presence_in(Ec::OperationAction::OPERATION_TYPES)
    @sku_operation_action_platform = params[:operation_action_platform].presence_in(Erp::OperationActionsController::PLATFORMS)
    page = (params[:jump_page].presence || params[:operation_actions_page]).to_i
    page = 1 unless page.positive?
    scope = @sku.operation_actions
      .preload(:operated_by_user, :store, :sku_product)
      .order(operated_at: :desc, id: :desc)
    scope = scope.where(operation_type: @sku_operation_action_type) if @sku_operation_action_type
    scope = scope.joins(:store).where(ec_stores: { platform: @sku_operation_action_platform }) if @sku_operation_action_platform
    @sku_operation_actions = scope
      .page(page)
      .per(10)
  end

  def load_sku_warehouses
    store_ids = @sku_products.map(&:store_id).uniq
    @stores = Ec::Store.active
      .where(id: store_ids, platform: %w[ozon wb])
      .where("(platform = 'ozon' AND ozon_raw_account_id IS NOT NULL) OR (platform = 'wb' AND wb_raw_account_id IS NOT NULL)")
      .order(:platform, :store_name)
    @store = @stores.find_by(id: params[:store_id]) || @stores.first
    @warehouse_platform = @store&.platform
    @warehouse_view = params[:view].to_s.in?(%w[products clusters]) ? params[:view].to_s : "products"
    @sku_warehouse_embed = true
    return unless @store

    query_class = @warehouse_platform == "wb" ? Ec::WbWarehouseRecommendationQuery : Ec::OzonWarehouseRecommendationQuery
    @target_days = params[:target_days].to_i
    @target_days = query_class::DEFAULT_TARGET_DAYS unless @target_days.positive?
    @target_days = [@target_days, query_class::MAX_TARGET_DAYS].min
    report = query_class.new(
      store: @store,
      from_date: user_today - 27.days,
      to_date: user_today,
      time_zone: user_time_zone,
      target_days: @target_days,
      sku_codes: [@sku.sku_code]
    ).call
    rows = @warehouse_view == "clusters" ? report[:cluster_rows] : report[:rows]
    paginated_rows = Kaminari.paginate_array(rows).page(warehouse_page_param).per(10)

    if @warehouse_platform == "wb"
      @wb_warehouse_view = @warehouse_view
      @wb_warehouse_report = report
      @wb_warehouse_rows = paginated_rows
    else
      @ozon_warehouse_view = @warehouse_view
      @ozon_warehouse_report = report
      @ozon_warehouse_rows = paginated_rows
    end
  end

  def sku_supply_order_columns(report)
    report.dig(:meta, :columns).map { |key| [key, t("supply_order_reports.columns.#{report.dig(:meta, :platform)}.#{key}")] }
  end

  def sku_supply_order_status_options
    values = @sku_supply_platform == "wb" ? SupplyOrderReports::ReportQuery::WB_STATUSES : SupplyOrderReports::ReportQuery::OZON_STATUSES
    values.map { |value| [t("supply_order_reports.statuses.#{@sku_supply_platform}.#{value}", default: value.to_s.humanize), value.to_s] }
  end

  def sku_supply_order_value(row, key)
    value = row[key]
    return "-" if value.nil? || value == ""
    return t("supply_order_reports.statuses.wb.#{value}", default: value) if key == :status && value.is_a?(Integer)
    return t("supply_order_reports.statuses.ozon.#{value}", default: value.to_s.humanize) if key == :status
    return helpers.display_time(value) if %i[created_at scheduled_at actual_at state_updated_at synced_at].include?(key)
    return [value["from"], value["to"]].compact.map { |time| helpers.display_time(time) }.join(" ~ ") if key == :timeslot && value.is_a?(Hash)
    return t(value ? "shared.yes" : "shared.no", default: value ? "Yes" : "No") if %i[pallet can_show_quantity].include?(key)

    value
  end

  def sku_operation_funnel_columns(report)
    report.dig(:meta, :columns).map do |key|
      [key, t("sales_funnel_reports.columns.#{report.dig(:meta, :platform)}.#{key}")]
    end
  end

  def sku_operation_profit_columns(report)
    keys = case report[:report_type]
    when "wr" then WeeklyProfitReportsController::WR_COLUMNS.fetch(report.dig(:meta, :platform))
    when "wsu" then WeeklyProfitReportsController::WSU_COLUMNS
    when "wsu_deep" then WeeklyProfitReportsController::WSU_DEEP_COLUMNS
    else []
    end
    keys.map { |key| [key, t("weekly_profit_reports.columns.#{report[:report_type]}.#{key}")] }
  end

  def sku_operation_report_value(row, key)
    value = row[key] || row[key.to_s]
    return "-" if value.nil? || value == ""
    return helpers.number_to_percentage(value, precision: 2) if key.to_s.match?(/(percent|conversion|rate|conv_to_cart|cart_to_order|buyout_percent|_pct|margin)\z/)
    return helpers.number_to_currency(value, unit: "", precision: 2) if key.to_s.match?(/(sum|amount|revenue)\z/)
    return format("%.2f", value) if value.is_a?(Float) || value.is_a?(BigDecimal)

    value
  end

  def sku_operation_row_comparison(report, row, key)
    row_key = if report[:report_type] == "wr"
      report.dig(:meta, :platform) == "wb" ? (row[:vendor_code].presence || row[:nm_id].to_s) : (row[:sku_code].presence || row[:ozon_sku_id].to_s)
    elsif report[:report_type] == "wsu"
      [row[:sku] || row["sku"], row[:platform] || row["platform"], row[:shop] || row["shop"]].join("|")
    elsif report[:report_type] == "wsu_deep"
      (row[:sku] || row["sku"]).to_s
    else
      row[:sku_code].to_s
    end
    report.dig(:comparison, :rows, row_key, key) || report.dig(:comparison, :rows, row_key.to_s, key.to_s)
  end

  def sku_operation_comparison_label(comparison)
    delta_pct = comparison&.dig(:delta_pct) || comparison&.dig("delta_pct")
    return t("weekly_profit_reports.comparison.unavailable") if delta_pct.nil?

    trend = comparison&.dig(:trend) || comparison&.dig("trend")
    arrow = trend == "up" ? "↗" : (trend == "down" ? "↘" : "→")
    "#{arrow} #{format('%.2f', delta_pct)}%"
  end

  def sku_operation_comparison_class(comparison)
    semantic = comparison&.dig(:semantic) || comparison&.dig("semantic")
    semantic.in?(%w[positive negative neutral]) ? "is-#{semantic}" : "is-none"
  end

  def report_value(value)
    return "-" if value.nil? || value == ""
    return format("%.2f", value) if value.is_a?(Float) || value.is_a?(BigDecimal)

    value
  end

  def parse_report_date(value)
    return if value.blank?

    Date.iso8601(value.to_s)
  rescue Date::Error, ArgumentError
    nil
  end

  def parse_decimal(value)
    return if value.blank?

    BigDecimal(value.to_s)
  rescue ArgumentError
    nil
  end

  def default_sku_detail_from_date
    @active_tab == "trend" ? 90.days.ago.to_date : 30.days.ago.to_date
  end

  def sku_detail_sales_period
    @active_tab == "stores" ? "range" : @period
  end

  def sku_detail_tab_path(tab, overrides = {})
    report_sku_path(@sku.sku_code, request.query_parameters.merge(overrides).merge(tab: tab).except(:sku_code))
  end

  def sku_detail_tabs
    SKU_DETAIL_TABS
  end

  def load_sku_search_terms
    @stores = Ec::Store.active.where(platform: SearchTermReports::Query::PLATFORMS).order(:platform, :store_name)
    requested_store = @stores.find_by(id: params[:store_id])
    @platform = requested_store&.platform || params[:platform].presence_in(SearchTermReports::Query::PLATFORMS) || "wb"
    @store = requested_store || @stores.find { |store| store.platform == @platform }
    @query = params[:q].to_s.strip

    default_monday = user_today.beginning_of_week(:monday) - 1.week
    @from_date = parse_report_date(params[:from_date]) || default_monday
    @to_date = parse_report_date(params[:to_date]) || default_monday.end_of_week(:monday)
    @valid_period = @from_date.monday? && @to_date.sunday? && @to_date == @from_date + 6.days
    return @rows = [] unless @store && @valid_period

    @previous_from_date = @from_date - 1.week
    @previous_to_date = @to_date - 1.week
    current_query = SearchTermReports::Query.new(
      platform: @platform, store: @store, period_from: @from_date, period_to: @to_date,
      sku_codes: [@sku.sku_code], query: @query
    )
    previous_query = SearchTermReports::Query.new(
      platform: @platform, store: @store, period_from: @previous_from_date, period_to: @previous_to_date,
      sku_codes: [@sku.sku_code], query: @query
    )
    @rows = current_query.rows
    @row_comparisons = SearchTermReports::ComparisonBuilder.new.rows(@rows, previous_query.rows)
  end

  def search_terms_metric(value, type: :number)
    return t("common.empty_value") if value.nil?

    case type
    when :currency then helpers.number_to_currency(value, unit: "₽", format: "%n %u", precision: 2)
    when :percentage then helpers.number_to_percentage(value, precision: 2)
    when :decimal then helpers.number_with_precision(value, precision: 2, strip_insignificant_zeros: true)
    else helpers.number_with_delimiter(value.to_i)
    end
  end

  def search_terms_metric_content(value, comparison, type: :number, comparison_type: :percentage)
    helpers.safe_join([
      helpers.content_tag(:span, search_terms_metric(value, type:)),
      helpers.content_tag(:div, search_terms_comparison_label(comparison, type: comparison_type),
        class: "weekly-profit-table-comparison #{search_terms_comparison_class(comparison)}")
    ])
  end

  def search_terms_comparison_label(comparison, type: :percentage)
    return t("reports.search_terms.comparison.unavailable") if comparison.blank? || comparison[:state] == :unavailable
    return t("reports.search_terms.comparison.new") if comparison[:state] == :new
    return t("reports.search_terms.comparison.lost.#{@platform}") if comparison[:state] == :lost

    value = type == :percentage ? comparison[:delta_pct] : comparison[:delta]
    return t("reports.search_terms.comparison.unavailable") if value.nil?
    return t("reports.search_terms.comparison.unchanged") if value.zero?

    key = value.positive? ? "up" : "down"
    formatted = helpers.number_with_precision(value.abs, precision: 2, strip_insignificant_zeros: true)
    t("reports.search_terms.comparison.#{type}.#{key}", value: formatted)
  end

  def search_terms_comparison_class(comparison)
    case comparison&.dig(:semantic)
    when :positive then "is-positive"
    when :negative then "is-negative"
    when :neutral then "is-neutral"
    else "is-none"
    end
  end

  def build_sku_sales_rows
    rows = sku_sales_relation

    rows.sort_by { |row| [row[:period_start], row[:sku_code].to_s, row[:platform].to_s, row[:store_name].to_s] }
  end

  def sku_detail_sales_rows(sku_products:, from_date:, to_date:, period:, grain:, platform: nil, store_id: nil)
    rows = sku_sales_relation_for(
      sku_product_ids: sku_products.map(&:id),
      from_date: from_date,
      to_date: to_date,
      period: period,
      grain: grain,
      platform: platform,
      store_id: store_id
    )

    rows.sort_by { |row| [row[:period_start], row[:sku_code].to_s, row[:platform].to_s, row[:store_name].to_s] }
  end

  def sku_sales_relation_for(sku_codes: nil, sku_product_ids: nil, from_date:, to_date:, period:, grain:, platform: nil, store_id: nil)
    Ec::SkuSalesQuery.new(
      sku_codes: sku_codes,
      sku_product_ids: sku_product_ids,
      from_date: from_date,
      to_date: to_date,
      period: period,
      grain: grain,
      time_zone: user_time_zone,
      platform: platform,
      store_id: store_id
    ).call
  end

  def sku_sales_relation
    sku_sales_relation_for(
      sku_product_ids: sku_product_ids_for(@selected_sku_codes),
      from_date: @from_date,
      to_date: @to_date,
      period: @period,
      grain: @grain,
      platform: @selected_platform,
      store_id: @selected_store_id
    )
  end

  def sku_product_ids_for(sku_codes)
    return nil if sku_codes.blank?

    Ec::SkuProduct.where(sku_code: sku_codes).pluck(:id)
  end

  def build_sku_sales_summary(rows)
    {
      sales_quantity: rows.sum { |row| row[:sales_quantity] },
      return_quantity: rows.sum { |row| row[:return_quantity] },
      net_quantity: rows.sum { |row| row[:net_quantity] },
      order_count: rows.sum { |row| row[:order_count] },
      gross_revenue: rows.sum { |row| row[:gross_revenue] },
      payout: rows.sum { |row| row[:payout] },
      commission: rows.sum { |row| row[:commission] }
    }
  end

  def build_sku_sales_chart_series(rows)
    rows
      .group_by { |row| [row[:sku_code], row[:platform], row[:store_name]] }
      .map do |(sku_code, platform, store_name), grouped_rows|
        {
          sku_code: sku_code,
          platform: platform,
          store_name: store_name,
          rows: grouped_rows.sort_by { |row| row[:period_start] }
        }
      end
      .sort_by { |series| [series[:sku_code].to_s, series[:platform].to_s, series[:store_name].to_s] }
  end

  def sku_sales_series_name(series)
    [series[:sku_code], platform_label_for_sales(series[:platform]), series[:store_name]].compact_blank.join(" / ")
  end

  def platform_label_for_sales(platform)
    t("common.platforms.#{platform}", default: platform.to_s)
  end

  def build_sku_sales_chart_option(series)
    periods = @sku_sales_rows.map { |row| row[:period_start].to_s }.uniq.sort
    net_sales_label = t("reports.sku_detail.metrics.net_sales")
    revenue_label = t("reports.sku_detail.metrics.revenue")
    {
      color: %w[#176b87 #b42318 #167044 #7c3aed #a15c07 #0f766e],
      tooltip: { trigger: "axis" },
      legend: {
        type: "scroll",
        top: 0,
        data: series.flat_map { |item| ["#{sku_sales_series_name(item)} #{net_sales_label}", "#{sku_sales_series_name(item)} #{revenue_label}"] }
      },
      grid: {
        left: 48,
        right: 24,
        top: 52,
        bottom: 42,
        containLabel: true
      },
      xAxis: {
        type: "category",
        boundaryGap: false,
        data: periods
      },
      yAxis: [
        { type: "value", name: net_sales_label, minInterval: 1 },
        { type: "value", name: revenue_label }
      ],
      series: series.flat_map do |item|
        values_by_period = item[:rows].index_by { |row| row[:period_start].to_s }
        name = sku_sales_series_name(item)
        [
          {
            name: "#{name} #{net_sales_label}",
            type: "line",
            smooth: true,
            symbolSize: 7,
            yAxisIndex: 0,
            data: periods.map { |period| values_by_period[period]&.fetch(:net_quantity, 0) || 0 }
          },
          {
            name: "#{name} #{revenue_label}",
            type: "line",
            smooth: true,
            symbolSize: 7,
            yAxisIndex: 1,
            data: periods.map { |period| values_by_period[period]&.fetch(:gross_revenue, 0)&.to_f || 0 }
          }
        ]
      end
    }
  end

  def selected_sku_codes
    values = params[:sku_codes].presence || params[:sku_code].presence
    Array(values).map(&:presence).compact
  end
end
