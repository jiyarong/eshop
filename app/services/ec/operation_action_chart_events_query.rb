module Ec
  class OperationActionChartEventsQuery
    def self.run(sku:, from_time:, to_time:, user_time_zone:, store: nil, sku_product: nil)
      new(sku:, from_time:, to_time:, user_time_zone:, store:, sku_product:).call
    end

    def initialize(sku:, from_time:, to_time:, user_time_zone:, store: nil, sku_product: nil)
      @sku = sku
      @from_time = from_time
      @to_time = to_time
      @time_zone = ActiveSupport::TimeZone[user_time_zone.to_s] || ActiveSupport::TimeZone[User::DEFAULT_TIME_ZONE]
      @store = store
      @sku_product = sku_product
    end

    def call
      scope = Ec::OperationAction
        .includes(:store, :sku, :sku_product, :operated_by_user)
        .where(ec_sku_id: @sku.id)
        .where("operated_at >= ? AND operated_at < ?", @from_time, @to_time)
      scope = scope.where(ec_store_id: @store.id) if @store
      scope = scope.where(ec_sku_product_id: @sku_product.id) if @sku_product

      scope.order(:operated_at, :id).map { |action| payload(action) }
    end

    private

    def payload(action)
      operated_at = action.operated_at.in_time_zone(@time_zone)
      product = action.sku_product

      {
        id: action.id,
        operated_at: operated_at.iso8601,
        event_date: operated_at.to_date.iso8601,
        operation_type: action.operation_type,
        operation_type_label: I18n.t("erp.operation_actions.operation_types.#{action.operation_type}"),
        platform: action.store.platform,
        platform_label: I18n.t("erp.operation_actions.platforms.#{action.store.platform}"),
        store_id: action.store.id,
        store_name: action.store.store_name,
        sku_code: action.sku.sku_code,
        sku_product_id: product.id,
        listing_label: product.product_name.presence || product.offer_id.presence || product.product_id,
        operator_name: action.operated_by_user.display_name,
        record_by_system: action.record_by_system,
        source_label: action.record_by_system ? I18n.t("reports.sku_detail.profit_analysis.events.system") : action.operated_by_user.display_name,
        diff_summary: Ec::OperationActionDiffFormatter.summary(action.diff_result, operation_type: action.operation_type),
        diff_result: action.diff_result
      }
    end
  end
end
