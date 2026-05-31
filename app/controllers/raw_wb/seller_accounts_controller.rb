module RawWb
  class SellerAccountsController < BaseController
    before_action :set_seller_account,  only: [:show, :update, :destroy]

    def index
      @seller_accounts = RawWb::SellerAccount.all
      @seller_accounts = @seller_accounts.where(account_id: params[:account_id]) if params[:account_id].present?
      @seller_accounts = @seller_accounts.page(params[:page]).per(params[:per_page] || 20)
    end

    def show; end

    def create
      @seller_account = RawWb::SellerAccount.new(seller_account_params)
      @seller_account.save!
      @message = 'Created successfully'
      render :show, status: :created
    end

    def update
      @seller_account.update!(seller_account_params)
      @message = 'Updated successfully'
      render :show
    end

    def destroy
      @seller_account.destroy!
      @message = 'Deleted successfully'
      render json: { success: true, data: nil, message: @message }
    end

    private

    def set_seller_account
      @seller_account = RawWb::SellerAccount.find(params[:id])
    end

    def seller_account_params
      params.require(:seller_account).permit!
    end
  end
end
