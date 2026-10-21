module Reports
  class DeliveryPlansController < DeliveryWorkbenchesController
    before_action -> { require_permission!(:manage_skus) }, except: %i[index show]
    before_action :find_delivery, except: %i[index create]

    def index
      hidden = Ec::DeliveryPlanItem.where.not(sku_code: access_scope.visible_skus.select(:sku_code))
      scope = Ec::DeliveryPlan.where.not(id: hidden.select(:delivery_plan_id)).includes(:store).order(week_start: :desc, id: :desc)
      scope = scope.where(store_id: params[:store_id]) if params[:store_id].present?
      scope = scope.where(status: params[:status]) if params[:status].present?
      @deliveries = scope.page(params[:page]).per(30)
      respond_to do |format|
        format.html
        format.json { render json: @deliveries }
      end
    end

    def show
      @allocated = @delivery.allocated_units
      @packing_plans = @delivery.packing_plans.includes(:ozon_supply_submission).order(id: :desc)
      respond_to do |format|
        format.html
        format.json { render json: @delivery.as_json.merge(items: @delivery.items, allocated_units: @allocated, packing_plans: @packing_plans) }
      end
    end

    def edit
      raise Ec::PalletPlans::Error.new(:delivery_inactive) unless @delivery.status == "active"
      params.merge!(store_id: @delivery.store_id, cluster_id: @delivery.macrolocal_cluster_id,
        from_date: @delivery.from_date.iso8601, to_date: @delivery.to_date.iso8601, target_days: @delivery.target_days)
      load_delivery_workbench
      render "reports/delivery_workbenches/show"
    end

    def create
      @delivery = Ec::DeliveryPlans::Save.new(user: current_user, attributes: delivery_attributes).call
      saved_delivery_response
    end

    def update
      @delivery = Ec::DeliveryPlans::Save.new(user: current_user, attributes: delivery_attributes, plan: @delivery).call
      saved_delivery_response
    end

    def cancel
      @delivery.with_lock do
        raise Ec::PalletPlans::Error.new(:delivery_has_packages) if @delivery.packing_plans.where.not(status: "cancelled").exists?
        @delivery.update!(status: "cancelled")
      end
      saved_delivery_response
    end

    private

    def find_delivery
      @delivery = Ec::DeliveryPlan.includes(:store, :items).find(params[:id])
      raise ActiveRecord::RecordNotFound if @delivery.items.where.not(sku_code: access_scope.visible_skus.select(:sku_code)).exists?
    end

    def delivery_attributes
      params.require(:delivery_plan).permit(:store_id, :cluster_id, :week_start, :from_date, :to_date,
        :target_days, :time_zone, :lock_version, items: %i[sku_code units]).to_h
    end

    def saved_delivery_response
      url = reports_delivery_plan_path(@delivery, locale: I18n.locale)
      respond_to do |format|
        format.html { redirect_to url, notice: t("delivery_workbench.saved"), status: :see_other }
        format.json { render json: @delivery.as_json.merge("url" => url) }
      end
    end
  end
end
