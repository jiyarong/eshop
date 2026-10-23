require "csv"

class OwnWarehouseCostsController < ApplicationController
  helper OwnWarehouseCostsHelper
  include SpuSkuFilterable
  include TableSortable

  before_action :authenticate_user!
  before_action -> { require_permission!(:view_reports) }
  before_action :require_finance_permission, only: [:create, :update, :confirm, :calculate, :template]

  COLUMNS = %w[
    sku_code own_warehouse_code week_start allocation_version on_hand_quantity on_hand_volume_m3
    fbs_outbound_quantity fbo_outbound_quantity storage_cost transport_cost labor_cost total_cost
    cost_per_outbound_unit
  ].freeze

  def index
    @active_tab = requested_tab
    if @active_tab == "config"
      require_finance_permission
      return if performed?
      load_configuration
    else
      load_report
    end

    respond_to do |format|
      format.html
      format.json { render_json_index }
    end
  rescue Date::Error, ArgumentError
    render_tab_error
  end

  def create
    @period = Ec::OwnWarehouseCostPeriod.new(period_params.merge(created_by_id: current_user.id))
    persist_period
  end

  def update
    @period = Ec::OwnWarehouseCostPeriod.find(params[:id])
    @period.with_lock do
      @period.assign_attributes(period_params)
      persist_period
    end
  end

  def confirm
    @period = Ec::OwnWarehouseCostPeriod.find(params[:id])
    @period.confirm!(actor: current_user)
    success_response
  rescue Ec::OwnWarehouseCostAllocator::InvalidInput, ActiveRecord::RecordInvalid => e
    failure_response(e.message)
  end

  def calculate
    @calculation_week = Date.iso8601(params.require(:week_start).to_s)
    unless @calculation_week.monday? && @calculation_week + 6 < user_today.beginning_of_week(:monday)
      raise Ec::OwnWarehouseCostAllocator::InvalidInput, :invalid_week
    end
    source_metadata = { source: "complete_daily_csv" }
    if params[:source] == "system"
      raise Ec::OwnWarehouseCostAllocator::InvalidInput, :unsupported_warehouse unless params[:own_warehouse_code] == "BY"
      system_inputs = Ec::OwnWarehouseCostInputTemplate.build(week_start: params.require(:week_start))
      rows = system_inputs.rows
      source_metadata = system_inputs.metadata
      raise Ec::OwnWarehouseCostAllocator::InvalidInput, :no_eligible_inputs if rows.empty?
    else
      raise Ec::OwnWarehouseCostAllocator::InvalidInput, :missing_inputs unless params[:complete_population] == "1" && params[:file].respond_to?(:read)
      raw = params[:file].read(5.megabytes + 1)
      raise Ec::OwnWarehouseCostAllocator::InvalidInput, :invalid_inputs if raw.bytesize > 5.megabytes
      rows = CSV.parse(raw.force_encoding("UTF-8").delete_prefix("\uFEFF"), headers: true).map(&:to_h)
    end
    Ec::OwnWarehouseCostAllocator.call(
      week_start: params.require(:week_start),
      warehouse_code: params.require(:own_warehouse_code),
      daily_inputs: rows,
      source_metadata: source_metadata,
      actor: current_user,
      required_sku_codes: params[:source] == "system" ? nil : Ec::Sku.active.pluck(:sku_code)
    )
    source_metadata = source_metadata.deep_stringify_keys
    issue_counts = source_metadata.fetch("issue_counts", {})
    excluded_count = source_metadata.fetch("excluded_skus", []).size
    notice_key = issue_counts.present? ? "own_warehouse.calculated_with_exclusions" : "own_warehouse.calculated"
    respond_to do |format|
      format.html { redirect_to own_warehouse_costs_path(calculation_report_params), notice: t(notice_key, count: excluded_count) }
      format.json { render json: { success: true, excluded_sku_count: excluded_count, issue_counts: issue_counts } }
    end
  rescue Ec::OwnWarehouseCostAllocator::InvalidInput, CSV::MalformedCSVError, Date::Error, ArgumentError, ActionController::ParameterMissing => e
    message = e.is_a?(Ec::OwnWarehouseCostAllocator::InvalidInput) ? e.message : t("own_warehouse.errors.invalid_inputs")
    respond_to do |format|
      format.html { redirect_to own_warehouse_costs_path(calculation_report_params), alert: message }
      format.json { render json: { error: message }, status: :unprocessable_entity }
    end
  end

  def template
    week_start = Date.iso8601(params[:week_start].presence || (user_today.beginning_of_week(:monday) - 7).to_s)
    rows = Ec::OwnWarehouseCostInputTemplate.call(week_start: week_start)
    send_data CSV.generate { |csv|
      csv << Ec::OwnWarehouseCostInputTemplate::HEADERS
      rows.each { |row| csv << Ec::OwnWarehouseCostInputTemplate::HEADERS.map { |key| row[key.to_sym] } }
    }, filename: "own_warehouse_daily_inputs_#{week_start}.csv", type: "text/csv"
  rescue Date::Error, ArgumentError
    head :unprocessable_entity
  end

  private

  def calculation_report_params
    result = { tab: "allocations", own_warehouse_code: params[:own_warehouse_code] }
    if @calculation_week&.monday? && @calculation_week + 6 < user_today.beginning_of_week(:monday)
      result.merge!(from_date: @calculation_week, to_date: @calculation_week + 6)
    end
    result
  end

  def requested_tab
    params[:tab].to_s == "allocations" ? "allocations" : "config"
  end

  def require_finance_permission
    require_permission!(:manage_finance)
  end

  def load_configuration
    @versions = Ec::OwnWarehouseCostPeriod.order(own_warehouse_code: :asc, effective_from: :desc, id: :desc)
    @period = params[:version_id].present? ? @versions.find(params[:version_id]) : @versions.first
    if params[:new_version].present?
      @period = @period&.dup || new_period
      @period.assign_attributes(status: "draft", effective_from: user_today, effective_to: nil, confirmed_at: nil, confirmed_by_id: nil, created_by_id: nil)
    end
    @period ||= new_period
  end

  def load_report
    default_week = user_today.beginning_of_week(:monday) - 7
    @from_date = params[:from_date].present? ? Date.iso8601(params[:from_date]) : default_week
    @to_date = params[:to_date].present? ? Date.iso8601(params[:to_date]) : default_week + 6
    access = WeeklyProfitReports::AccessScope.new(current_user)
    load_spu_sku_filter(master_skus: access.visible_master_skus, orphan_skus: access.visible_orphan_skus, allowed_sku_codes: access.restricted? ? access.visible_sku_codes : nil)
    skus = apply_spu_sku_filter_to_skus(access.visible_skus)
    @warehouses = Ec::OwnWarehouseCostPeriod.published.distinct.order(:own_warehouse_code).pluck(:own_warehouse_code)
    @warehouse_code = params[:own_warehouse_code].to_s.presence || @warehouses.first || "BY"
    @show_history = params[:history] == "1"
    @valid_week = @from_date.monday? && @to_date == @from_date + 6 && @to_date < user_today.beginning_of_week(:monday)
    unless @valid_week
      @report_error = t("own_warehouse.errors.invalid_week")
      @rows, @revisions = [], []
      @total_count, @total_cost = 0, 0
      return
    end

    week_scope = Ec::OwnWarehouseSkuCostAllocation.where(own_warehouse_code: @warehouse_code, week_start: @from_date)
    @week_generated = can?(:manage_finance) && week_scope.exists?
    scope = week_scope.where(sku_id: skus.select(:id))
    @revisions = scope.distinct.order(allocation_version: :desc).pluck(:allocation_version)
    @revision = Integer(params[:revision], exception: false)
    @revision = nil unless @revisions.include?(@revision)
    scope = if @revision
      scope.where(allocation_version: @revision)
    elsif @show_history
      scope
    else
      scope.current
    end
    latest_inputs = scope.order(id: :desc).limit(1).pick(:calculation_inputs) || {}
    @input_warnings = latest_inputs.fetch("source_metadata", {}).fetch("issue_counts", {})
    load_table_sort(allowed_keys: COLUMNS, default_key: "total_cost")
    order = table_sort_key == "sku_code" ? "ec_skus.sku_code" : "ec_own_warehouse_sku_cost_allocations.#{table_sort_key}"
    @total_count = scope.count
    @total_cost = scope.sum(:total_cost)
    @page = [params[:page].to_i, 1].max
    @page_count = [(@total_count / 50.0).ceil, 1].max
    @page = [@page, @page_count].min
    @rows = scope.joins(:sku).includes(:sku).order(Arel.sql("#{order} #{table_sort_direction} NULLS LAST, ec_own_warehouse_sku_cost_allocations.id ASC")).limit(50).offset((@page - 1) * 50).to_a
  end

  def render_json_index
    if @active_tab == "config"
      render json: { period: @period, versions: @versions }
    else
      result = { rows: @rows.as_json(include: { sku: { only: :sku_code } }), total_count: @total_count, total_cost: @total_cost }
      result[:error] = @report_error if @report_error
      render json: result, status: @report_error ? :unprocessable_entity : :ok
    end
  end

  def render_tab_error
    respond_to do |format|
      format.html { render plain: t("own_warehouse.errors.invalid_week"), status: :unprocessable_entity }
      format.json { render json: { error: t("own_warehouse.errors.invalid_week") }, status: :unprocessable_entity }
    end
  end

  def new_period
    Ec::OwnWarehouseCostPeriod.new(
      own_warehouse_code: "BY", effective_from: user_today, currency: "CNY",
      total_operating_cost: 9300, cost_basis_days: 7, storage_ratio: 0.4, transport_ratio: 0.25,
      labor_ratio: 0.35, fbo_labor_weight: 0.1,
      source_reference: "白俄海外仓成本分摊自动化核算表.xlsx"
    )
  end

  def period_params
    params.require(:ec_own_warehouse_cost_period).permit(:own_warehouse_code, :effective_from, :effective_to, :total_operating_cost, :cost_basis_days, :currency, :storage_ratio, :transport_ratio, :labor_ratio, :fbo_labor_weight, :source_reference, :note)
  end

  def persist_period
    @period.save ? success_response : failure_response(@period.errors.full_messages.join(", "))
  rescue ActiveRecord::RecordNotUnique
    failure_response(t("own_warehouse.errors.overlap"))
  end

  def success_response
    respond_to do |format|
      format.html { redirect_to own_warehouse_costs_path(tab: "config", version_id: @period.id), notice: t("own_warehouse.saved") }
      format.json { render json: @period }
    end
  end

  def failure_response(message)
    @active_tab = "config"
    @versions = Ec::OwnWarehouseCostPeriod.order(effective_from: :desc)
    @error = message
    respond_to do |format|
      format.html { render :index, status: :unprocessable_entity }
      format.json { render json: { error: message }, status: :unprocessable_entity }
    end
  end
end
