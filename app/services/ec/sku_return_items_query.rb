module Ec
  class SkuReturnItemsQuery
    PAGE_SIZE = 10
    RESTOCKABLE_FILTERS = %w[true false].freeze

    def self.scope_for_linked_orders(sku)
      Ec::ReturnItem
        .joins(:sku_product, return: :order)
        .where(ec_sku_products: { sku_code: sku.sku_code })
    end

    def self.scope_for(sku)
      scope_for_linked_orders(sku)
        .where.not(ec_orders: { order_status: "cancelled" })
    end

    def initialize(sku, page:, restockable:)
      @sku = sku
      @requested_page = [page.to_i, 1].max
      @restockable_filter = restockable.to_s.presence_in(RESTOCKABLE_FILTERS)
    end

    def call
      filtered_scope = apply_filter(self.class.scope_for(@sku))
      total_count = filtered_scope.count
      total_pages = [(total_count / PAGE_SIZE.to_f).ceil, 1].max
      page = [@requested_page, total_pages].min

      {
        rows: rows(filtered_scope, page),
        restockable_filter: @restockable_filter,
        pagination: {
          page: page,
          page_size: PAGE_SIZE,
          total_count: total_count,
          total_pages: total_pages
        }
      }
    end

    private

    def apply_filter(scope)
      return scope unless @restockable_filter

      scope.where(restockable: @restockable_filter == "true")
    end

    def rows(scope, page)
      scope
        .includes(:store, :sku_product, return: :order)
        .order(Arel.sql("COALESCE(ec_returns.requested_at, ec_returns.created_at) DESC"), id: :desc)
        .limit(PAGE_SIZE)
        .offset((page - 1) * PAGE_SIZE)
        .map do |item|
          {
            id: item.id,
            platform: item.platform,
            store_name: item.store.store_name,
            external_return_id: item.return.external_return_id,
            external_order_number: item.return.external_order_number.presence || item.return.external_order_id,
            process_status: item.return.process_status,
            source_status: item.return.source_status,
            quantity: item.quantity,
            requested_at: item.return.requested_at,
            restockable: item.restockable
          }
        end
    end
  end
end
