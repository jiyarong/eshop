module Reports
  class PalletPlansController < PalletWorkbenchesController
    before_action -> { require_permission!(:manage_skus) }, except: %i[index show supply_submission_status]
    before_action :find_plan, except: %i[index create]

    def index
      scope = Ec::PalletPlan.includes(:store, :ozon_supply_submission).order(id: :desc)
      hidden_items = Ec::PalletPlanItem.where.not(sku_code: access_scope.visible_skus.select(:sku_code))
      scope = scope.where.not(id: hidden_items.select(:pallet_plan_id))
      scope = scope.where(store_id: params[:store_id]) if params[:store_id].present?
      scope = scope.where(status: params[:status]) if params[:status].present?
      @plans = scope.page(params[:page]).per(30)
      respond_to do |format|
        format.html
        format.json { render json: @plans.map { |plan| plan_data(plan) } }
      end
    end

    def show
      @result = @plan.calculation.deep_symbolize_keys
      respond_to do |format|
        format.html
        format.json { render json: plan_data(@plan).merge(items: @plan.items, calculation: @plan.calculation) }
      end
    end

    def edit
      raise Ec::PalletPlans::Error.new(:not_editable) unless @plan.editable?
      params[:store_id] = @plan.store_id
      params[:cluster_id] = @plan.macrolocal_cluster_id
      params[:from_date] = @plan.from_date.iso8601
      params[:to_date] = @plan.to_date.iso8601
      params[:target_days] = @plan.target_days
      load_workbench
      render "reports/pallet_workbenches/show"
    end

    def create
      @plan = Ec::PalletPlans::Save.new(user: current_user, attributes: plan_attributes).call
      saved_response
    end

    def update
      @plan = Ec::PalletPlans::Save.new(user: current_user, plan: @plan, attributes: plan_attributes).call
      saved_response
    end

    def confirm
      workflow.confirm!
      saved_response
    end

    def advance
      workflow.advance!(params[:status].to_s, platform_check_note: params[:platform_check_note])
      saved_response
    end

    def cancel
      workflow.cancel!
      saved_response
    end

    def bind
      workflow.bind!(params[:supply_order_number].to_s.strip)
      saved_response
    end

    def supply_orders
      bound_orders = Ec::PalletPlan.where(store_id: @plan.store_id).where.not(id: @plan.id)
        .where.not(status: "cancelled").where.not(ozon_order_id: nil).select(:ozon_order_id)
      options = SupplyOrderReports::ReportQuery.new(params: {
        store_ref: "ozon:#{@plan.store.ozon_raw_account_id}", q: params[:q]
      }).ozon_order_options(platform_sku_ids: @plan.items.map(&:platform_sku_id),
        cluster_id: @plan.macrolocal_cluster_id, excluded_order_ids: bound_orders)

      render json: options.map { |option| { id: option[:id], label: t("pallet_workbench.supply_option",
        number: option[:order_number], status: t("supply_order_reports.statuses.ozon.#{option[:status]}", default: option[:status])) } }
    end

    def refresh
      workflow.refresh!
      saved_response
    end

    def supply_submission_status
      render json: { running: @plan.ozon_supply_submission&.running?, active: @plan.active?, state: @plan.ozon_supply_submission&.state,
        html: render_to_string(partial: "reports/pallet_plans/supply_submission", formats: [:html], locals: { plan: @plan }),
        workflow_html: render_to_string(partial: "reports/pallet_plans/workflow", formats: [:html], locals: { plan: @plan }), plan_state: @plan.status,
        platform_status: @plan.platform_status, platform_synced_at: helpers.display_time(@plan.platform_synced_at),
        status: helpers.pallet_workbench_status(@plan), order_number: @plan.supply_order_number, sync_error: @plan.sync_error }
    end

    def supply_warehouse
      supply_actions.select_warehouse!(params[:warehouse_id])
      enqueue_supply
    end

    def submit_supply
      supply_actions.submit!(params[:timeslot_index])
      enqueue_supply
    end

    def retry_supply
      supply_actions.retry!
      enqueue_supply
    end

    def cancel_supply
      supply_actions.cancel!
      saved_response
    end

    private

    def find_plan
      @plan = Ec::PalletPlan.includes(:store, :items, :pallets, :ozon_supply_submission).find(params[:id])
      raise ActiveRecord::RecordNotFound if @plan.items.where.not(sku_code: access_scope.visible_skus.select(:sku_code)).exists?
    end

    def supply_actions
      raise ActiveRecord::RecordNotFound unless @plan.ozon_supply_submission
      Ec::PalletPlans::OzonSupplyActions.new(submission: @plan.ozon_supply_submission)
    end

    def enqueue_supply
      Ec::OzonSupplySubmissionJob.perform_later(@plan.ozon_supply_submission.id)
      saved_response
    end

    def workflow
      Ec::PalletPlans::Workflow.new(plan: @plan, user: current_user)
    end

    def plan_data(plan)
      plan.as_json(only: %i[id plan_no store_id macrolocal_cluster_id cluster_name status supply_order_number ozon_order_id platform_status platform_synced_at sync_error lock_version created_at])
        .merge("supply_submission" => plan.ozon_supply_submission&.as_json(only: %i[id state draft_id order_id last_error]))
    end

    def saved_response
      respond_to do |format|
        format.html { redirect_to reports_pallet_plan_path(@plan), notice: t("pallet_workbench.saved"), status: :see_other }
        format.json { render json: plan_data(@plan).merge("url" => reports_pallet_plan_path(@plan, locale: I18n.locale)) }
      end
    end
  end
end
