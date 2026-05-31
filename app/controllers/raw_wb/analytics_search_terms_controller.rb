module RawWb
  class AnalyticsSearchTermsController < BaseController
    before_action :set_analytics_search_term,  only: [:show, :update, :destroy]

    def index
      @analytics_search_terms = RawWb::AnalyticsSearchTerm.all
      @analytics_search_terms = @analytics_search_terms.where(account_id: params[:account_id]) if params[:account_id].present?
      @analytics_search_terms = @analytics_search_terms.page(params[:page]).per(params[:per_page] || 20)
    end

    def show; end

    def create
      @analytics_search_term = RawWb::AnalyticsSearchTerm.new(analytics_search_term_params)
      @analytics_search_term.save!
      @message = 'Created successfully'
      render :show, status: :created
    end

    def update
      @analytics_search_term.update!(analytics_search_term_params)
      @message = 'Updated successfully'
      render :show
    end

    def destroy
      @analytics_search_term.destroy!
      @message = 'Deleted successfully'
      render json: { success: true, data: nil, message: @message }
    end

    private

    def set_analytics_search_term
      @analytics_search_term = RawWb::AnalyticsSearchTerm.find(params[:id])
    end

    def analytics_search_term_params
      params.require(:analytics_search_term).permit!
    end
  end
end
