module Ec
  module PalletPlans
    class ListingSelection
      def initialize(products:)
        @products = products.to_a
      end

      def call
        candidates = @products.group_by(&:sku_code).transform_values do |products|
          products.one? ? products : products.select(&:is_active?)
        end
        order_times = latest_order_times(candidates.values.select(&:many?).flatten)

        candidates.transform_values do |products|
          next products.first if products.one?

          latest_time = products.filter_map { |product| order_times[product.id] }.max
          next unless latest_time

          latest = products.select { |product| order_times[product.id] == latest_time }
          latest.first if latest.one?
        end
      end

      private

      def latest_order_times(products)
        return {} if products.empty?

        Ec::SkuProduct.where(id: products.map(&:id))
          .joins(<<~SQL.squish)
            INNER JOIN ec_order_items
              ON ec_order_items.store_id = ec_sku_products.store_id
             AND ec_order_items.platform = ec_sku_products.platform
             AND ec_order_items.platform_sku_id = ec_sku_products.platform_sku_id
            INNER JOIN ec_orders ON ec_orders.id = ec_order_items.order_id
          SQL
          .group(:id).maximum("ec_orders.ordered_at")
      end
    end
  end
end
