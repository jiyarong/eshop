module RawWb
  class ReturnClaimsController < BaseController
    before_action :set_return_claim,  only: [:show, :update, :destroy]

    def index
      @return_claims = RawWb::ReturnClaim.all
      @return_claims = @return_claims.where(account_id: params[:account_id]) if params[:account_id].present?
      @return_claims = @return_claims.page(params[:page]).per(params[:per_page] || 20)
    end

    def show; end

    def create
      @return_claim = RawWb::ReturnClaim.new(return_claim_params)
      @return_claim.save!
      @message = 'Created successfully'
      render :show, status: :created
    end

    def update
      @return_claim.update!(return_claim_params)
      @message = 'Updated successfully'
      render :show
    end

    def destroy
      @return_claim.destroy!
      @message = 'Deleted successfully'
      render json: { success: true, data: nil, message: @message }
    end

    private

    def set_return_claim
      @return_claim = RawWb::ReturnClaim.find(params[:id])
    end

    def return_claim_params
      params.require(:return_claim).permit!
    end
  end
end
