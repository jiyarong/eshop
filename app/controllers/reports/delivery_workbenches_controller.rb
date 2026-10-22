module Reports
  class DeliveryWorkbenchesController < PalletWorkbenchesController
    def show
      load_delivery_workbench
      respond_to do |format|
        format.html
        format.json { render json: { store_id: @store&.id, cluster_id: @cluster_id, clusters: @clusters, week_start: @week_start, rows: @catalogue } }
      end
    end

    private

    def load_delivery_workbench
      load_workbench
      @week_start = (@delivery&.week_start || (params[:week_start].present? ? Date.iso8601(params[:week_start].to_s) : user_today)).beginning_of_week(:monday)
      @catalogue.each { |row| row[:suggested_units] = @cluster_id ? [row[:shortage].to_i, [row[:fbs_allocatable].to_i, 0].max].min : 0 }
      unless @cluster_id
        @catalogue.sort_by! { |row| row[:sku_code].to_s }
        @rows = Kaminari.paginate_array(@catalogue).page(params[:page]).per(15)
      end
      load_sales_metrics
    end
  end
end
