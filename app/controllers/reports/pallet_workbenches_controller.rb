module Reports
  class PalletWorkbenchesController < ApplicationController
    include ResponsibleUserFilterable
    include SpuSkuFilterable
    include TableSortable

    SORT_KEYS = %w[sku_code shortage daily_sales sales_quantity days_of_stock fbs_allocatable available inbound].freeze

    before_action -> { require_permission!(:view_reports) }
    before_action -> { require_permission!(:manage_skus) }, only: :auto_select
    before_action :load_preview_plan, only: %i[preview auto_select]

    rescue_from Ec::PalletPlans::Error, PalletPacking::Calculator::InvalidInput, with: :render_workbench_error
    rescue_from ActionController::ParameterMissing, ArgumentError, with: :render_invalid_input

    def show
      load_workbench
      respond_to do |format|
        format.html
        format.json { render json: { store_id: @store&.id, clusters: @clusters, cluster_id: @cluster_id, rows: @catalogue, inventory_synced_at: @inventory_synced_at } }
      end
    end

    def preview
      built = Ec::PalletPlans::Build.new(user: current_user, attributes: plan_attributes, existing_plan: @plan).call
      @result = built.fetch(:result).deep_symbolize_keys
      respond_to do |format|
        format.html { render partial: "reports/pallet_workbenches/result", locals: { result: @result } }
        format.json do
          render json: { result: @result, html: render_to_string(partial: "reports/pallet_workbenches/result", formats: [:html], locals: { result: @result }) }
        end
      end
    end

    def auto_select
      load_workbench(operator_override: ActiveModel::Type::Boolean.new.cast(params[:my_skus]) ? current_user.id : nil)
      threshold = Integer(params[:shortage_gt].presence || 10)
      selected, excluded = @catalogue.partition do |row|
        row[:shortage].to_i > threshold && row[:packaging_complete] && row[:suggested_boxes].to_i.positive?
      end
      render json: { items: selected.map { |row| { sku_code: row[:sku_code], quantity: row[:suggested_boxes] } }, selected_count: selected.size,
        excluded: excluded.map { |row| { sku_code: row[:sku_code], reason: row[:exclusion_reason].presence || (row[:shortage].to_i <= threshold ? "below_threshold" : "stock_unavailable") } } }
    end

    private

    def access_scope
      @access_scope ||= WeeklyProfitReports::AccessScope.new(current_user)
    end

    def load_preview_plan
      plan_id = params.dig(:pallet_plan, :plan_id).presence || params[:plan_id].presence
      return unless plan_id

      @plan = Ec::PalletPlan.find(plan_id)
      raise ActiveRecord::RecordNotFound if @plan.items.where.not(sku_code: access_scope.visible_skus.select(:sku_code)).exists?
      raise Ec::PalletPlans::Error.new(:not_editable) unless @plan.editable?
    end

    def load_workbench(operator_override: nil)
      @stores = Ec::Store.active.where(platform: "ozon").where.not(ozon_raw_account_id: nil).order(:store_name)
      @store = params[:store_id].present? ? @stores.find(params[:store_id]) : @stores.first
      @clusters = @store ? RawOzon::WarehouseCluster.where(account_id: @store.ozon_raw_account_id).where.not(macrolocal_cluster_id: nil)
        .group(:macrolocal_cluster_id).order(Arel.sql("MIN(cluster_name)"))
        .pluck(:macrolocal_cluster_id, Arel.sql("MIN(cluster_name)")).map { |id, name| { id: id, name: name.presence || id.to_s } } : []
      @cluster_id = params[:cluster_id].presence&.to_i
      raise Ec::PalletPlans::Error.new(:cluster_unavailable) if @cluster_id && @clusters.none? { |cluster| cluster[:id] == @cluster_id }
      @from_date = params[:from_date].present? ? Date.iso8601(params[:from_date].to_s) : user_today - 28
      @to_date = params[:to_date].present? ? Date.iso8601(params[:to_date].to_s) : user_today - 1
      @target_days = Integer(params[:target_days].presence || 28)
      raise Ec::PalletPlans::Error.new(:invalid_period) unless @from_date <= @to_date && @target_days.between?(1, 180)
      load_responsible_user_filters
      visible_skus = access_scope.visible_skus
      load_spu_sku_filter(master_skus: access_scope.visible_master_skus, orphan_skus: access_scope.visible_orphan_skus,
        allowed_sku_codes: visible_skus.pluck(:sku_code))
      sku_scope = apply_spu_sku_filter_to_skus(visible_skus)
      @catalogue = []
      if @store && @clusters.any?
        report_cluster_id = @cluster_id || @clusters.first[:id]
        report = Ec::PalletPlans::WorkbenchQuery.new(user: current_user, store: @store, cluster_id: report_cluster_id,
          from_date: @from_date, to_date: @to_date, time_zone: user_time_zone, target_days: @target_days,
          query: params[:q], operator_id: operator_override || @operator_id, developer_id: @developer_id,
          sku_codes: sku_scope.select(:sku_code), excluding_plan_id: @plan&.id).call
        gaps_by_cluster = report.fetch(:cluster_rows).index_by { |row| row[:cluster_name].to_s }
        @clusters = @clusters.map do |cluster|
          cluster.merge(shortage: gaps_by_cluster.dig(cluster[:name].to_s, :distribution_gap).to_i)
        end.sort_by { |cluster| [-cluster[:shortage], cluster[:name].to_s] }

        if @cluster_id
          @catalogue = report.fetch(:rows)
          @inventory_synced_at = report[:inventory_synced_at]
          @catalogue.select! { |row| row[:shortage].to_f > params[:shortage_gt].to_f } if params[:shortage_gt].present?
          @catalogue.select! { |row| row[:packaging_complete] } if params[:packaging_complete] == "1"
          @catalogue.select! { |row| row[:fbs_allocatable].to_i >= row[:pcs].to_i && row[:pcs].to_i.positive? } if params[:allocatable_only] == "1"
        end
      end
      load_table_sort(allowed_keys: SORT_KEYS, default_key: :shortage)
      @catalogue = sort_table_records(@catalogue) { |row| row[table_sort_key.to_sym] }
      @rows = Kaminari.paginate_array(@catalogue).page(params[:page]).per(15)
    end

    def plan_attributes
      source = params[:pallet_plan].presence || params
      source.permit(:plan_id, :store_id, :cluster_id, :from_date, :to_date, :target_days, :time_zone, :lock_version, :packing_mode, :recommend_one,
        settings: PalletPacking::Rules.defaults("ozon_fbo").keys,
        items: %i[sku_code quantity length width height weight pcs unit_volume_l rotatable],
        allocations: [items: %i[sku_code quantity]]).to_h
    end

    def render_workbench_error(error)
      details = error.details.transform_values { |value| value.is_a?(Symbol) ? t("pallet_calculator.fields.#{value}", default: value.to_s) : value }
      @error = t("pallet_workbench.errors.#{error.key}", **details, default: t("pallet_calculator.errors.#{error.key}", **details, default: t("pallet_workbench.errors.invalid_input")))
      respond_to do |format|
        format.html { render partial: "reports/pallet_workbenches/error", status: :unprocessable_entity }
        format.json { render json: { error: @error, key: error.key, details: error.details }, status: :unprocessable_entity }
      end
    end

    def render_invalid_input(_error)
      @error = t("pallet_workbench.errors.invalid_input")
      respond_to do |format|
        format.html { render partial: "reports/pallet_workbenches/error", status: :unprocessable_entity }
        format.json { render json: { error: @error }, status: :unprocessable_entity }
      end
    end
  end
end
