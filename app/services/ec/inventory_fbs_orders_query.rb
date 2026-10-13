module Ec
  # Orders behind one cell of the FBS status matrix of a SKU.
  class InventoryFbsOrdersQuery
    PAGE_SIZE = 20
    ORDER_ITEM_JOIN = Ec::InventoryFbsStatusMatrixQuery::ORDER_ITEM_JOIN

    def initialize(sku, business_status:, return_business_status:, page: 1)
      @sku = sku
      @business_status = business_status
      @return_business_status = return_business_status
      @requested_page = [ page.to_i, 1 ].max
    end

    def call
      total_count = scope.count
      total_pages = [ (total_count / PAGE_SIZE.to_f).ceil, 1 ].max
      page = [ @requested_page, total_pages ].min
      labeler = Ec::InventoryOrderSalesDistributionQuery.new(@sku)

      rows = scope
        .order(Arel.sql("ec_orders.ordered_at DESC NULLS LAST"), Arel.sql("ec_order_items.id DESC"))
        .offset((page - 1) * PAGE_SIZE).limit(PAGE_SIZE)
        .pluck(
          "ec_order_items.platform", "ec_stores.store_name", "ec_orders.external_order_number",
          "ec_order_fulfillments.external_fulfillment_id", "ec_orders.ordered_at",
          "ec_order_fulfillments.source_status", "ec_order_fulfillments.source_substatus",
          "ec_order_items.quantity"
        ).map do |platform, store_name, order_number, fulfillment_number, ordered_at, source_status, source_substatus, quantity|
          {
            platform: platform,
            store_name: store_name,
            order_number: order_number,
            fulfillment_number: fulfillment_number,
            ordered_at: ordered_at,
            business_status: @business_status,
            return_business_status: @return_business_status,
            source_status_label: labeler.source_status_label(platform, source_status, source_substatus),
            quantity: quantity.to_i
          }
        end

      {
        rows: rows,
        total_quantity: scope.sum("ec_order_items.quantity").to_i,
        pagination: { page: page, per_page: PAGE_SIZE, total_count: total_count, total_pages: total_pages }
      }
    end

    private

    def scope
      @scope ||= Ec::OrderItem
        .joins(:fulfillment, :order, :store)
        .joins(ORDER_ITEM_JOIN)
        .where(ec_sku_products: { sku_code: @sku.sku_code })
        .where(ec_order_fulfillments: {
          fulfillment_type: "fbs", business_status: @business_status,
          return_business_status: @return_business_status
        })
    end
  end
end
