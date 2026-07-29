module Erp
  class OperationActionsController < BaseController
    PAGE_SIZE = 10
    PLATFORMS = %w[wb ozon].freeze

    def index
      @operation_type = params[:operation_type].presence_in(Ec::OperationAction::OPERATION_TYPES)
      @platform = params[:platform].presence_in(PLATFORMS)
      @sku_query = params[:sku].to_s.strip

      scope = Ec::OperationAction
        .preload(:operated_by_user, :sku, :store, :sku_product)
        .order(operated_at: :desc, id: :desc)
      scope = scope.where(operation_type: @operation_type) if @operation_type
      scope = scope.joins(:store).where(ec_stores: { platform: @platform }) if @platform
      if @sku_query.present?
        keyword = "%#{ActiveRecord::Base.sanitize_sql_like(@sku_query)}%"
        scope = scope.joins(:sku).where("ec_skus.sku_code ILIKE ?", keyword)
      end

      @operation_actions = scope.page(page_param).per(PAGE_SIZE)
    end

    private

    def page_param
      requested_page = params[:jump_page].presence || params[:page].presence
      page = requested_page.to_i
      page.positive? ? page : 1
    end
  end
end
