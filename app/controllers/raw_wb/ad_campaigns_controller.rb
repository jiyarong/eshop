module RawWb
  class AdCampaignsController < BaseController
    before_action :set_ad_campaign,  only: [:show, :update, :destroy]

    def index
      @ad_campaigns = RawWb::AdCampaign.all
      @ad_campaigns = @ad_campaigns.where(account_id: params[:account_id]) if params[:account_id].present?
      @ad_campaigns = @ad_campaigns.page(params[:page]).per(params[:per_page] || 20)
    end

    def show; end

    def create
      @ad_campaign = RawWb::AdCampaign.new(ad_campaign_params)
      @ad_campaign.save!
      @message = 'Created successfully'
      render :show, status: :created
    end

    def update
      @ad_campaign.update!(ad_campaign_params)
      @message = 'Updated successfully'
      render :show
    end

    def destroy
      @ad_campaign.destroy!
      @message = 'Deleted successfully'
      render json: { success: true, data: nil, message: @message }
    end

    private

    def set_ad_campaign
      @ad_campaign = RawWb::AdCampaign.find(params[:id])
    end

    def ad_campaign_params
      params.require(:ad_campaign).permit!
    end
  end
end
