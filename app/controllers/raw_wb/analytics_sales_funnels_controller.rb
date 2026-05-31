module RawWb
  class AnalyticsSalesFunnelsController < BaseController
    before_action :set_analytics_sales_funnel,  only: [:show, :update, :destroy]

    def index
      @analytics_sales_funnels = RawWb::AnalyticsSalesFunnel.all
      @analytics_sales_funnels = @analytics_sales_funnels.where(account_id: params[:account_id]) if params[:account_id].present?
      @analytics_sales_funnels = @analytics_sales_funnels.page(params[:page]).per(params[:per_page] || 20)
    end

    def show; end

    def create
      @analytics_sales_funnel = RawWb::AnalyticsSalesFunnel.new(analytics_sales_funnel_params)
      @analytics_sales_funnel.save!
      @message = 'Created successfully'
      render :show, status: :created
    end

    def update
      @analytics_sales_funnel.update!(analytics_sales_funnel_params)
      @message = 'Updated successfully'
      render :show
    end

    def destroy
      @analytics_sales_funnel.destroy!
      @message = 'Deleted successfully'
      render json: { success: true, data: nil, message: @message }
    end

    private

    def set_analytics_sales_funnel
      @analytics_sales_funnel = RawWb::AnalyticsSalesFunnel.find(params[:id])
    end

    def analytics_sales_funnel_params
      params.require(:analytics_sales_funnel).permit!
    end
  end
end
