module Ec
  module DeliveryPlans
    class Allocation
      def self.validate!(plan:, store:, cluster:, items:)
        raise PalletPlans::Error.new(:delivery_inactive) unless plan.status == "active"
        raise PalletPlans::Error.new(:invalid_store) unless plan.store_id == store.id
        raise PalletPlans::Error.new(:invalid_cluster) unless plan.macrolocal_cluster_id == cluster.macrolocal_cluster_id
        expected = plan.items.index_by(&:sku_code)
        items.each do |item|
          code = item.fetch(:sku_code)
          raise PalletPlans::Error.new(:delivery_sku_unavailable, sku: code) unless expected.key?(code)
        end
      end
    end
  end
end
