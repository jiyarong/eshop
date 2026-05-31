module RawWb
  class AccountBalancesController < BaseController
    before_action :set_account_balance,  only: [:show, :update, :destroy]

    def index
      @account_balances = RawWb::AccountBalance.all
      @account_balances = @account_balances.where(account_id: params[:account_id]) if params[:account_id].present?
      @account_balances = @account_balances.page(params[:page]).per(params[:per_page] || 20)
    end

    def show; end

    def create
      @account_balance = RawWb::AccountBalance.new(account_balance_params)
      @account_balance.save!
      @message = 'Created successfully'
      render :show, status: :created
    end

    def update
      @account_balance.update!(account_balance_params)
      @message = 'Updated successfully'
      render :show
    end

    def destroy
      @account_balance.destroy!
      @message = 'Deleted successfully'
      render json: { success: true, data: nil, message: @message }
    end

    private

    def set_account_balance
      @account_balance = RawWb::AccountBalance.find(params[:id])
    end

    def account_balance_params
      params.require(:account_balance).permit!
    end
  end
end
