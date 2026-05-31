module Ec
  class CostAllocationBuilder
    def initialize(total_amount_cny:, allocation_method:, batches:)
      @total_amount_cny = total_amount_cny.to_d
      @allocation_method = allocation_method
      @batches = batches
    end

    def call
      weights = batches.to_h { |batch| [batch.id, weight_for(batch)] }
      total_weight = weights.values.sum.to_d
      return batches.to_h { |batch| [batch.id, 0.to_d] } if total_weight.zero?

      allocate_by_weights(weights, total_weight)
    end

    private

    attr_reader :total_amount_cny, :allocation_method, :batches

    def weight_for(batch)
      case allocation_method
      when "by_quantity"
        batch.costing_quantity.to_d
      when "by_purchase_amount"
        batch.costing_quantity.to_d * batch.purchase_unit_price_cny.to_d
      else
        raise ArgumentError, "unsupported allocation method: #{allocation_method}"
      end
    end

    def allocate_by_weights(weights, total_weight)
      allocated = {}
      remainder = total_amount_cny
      last_id = weights.keys.last

      weights.each do |batch_id, weight|
        amount = if batch_id == last_id
          remainder
        else
          (total_amount_cny * weight / total_weight).round(4)
        end
        allocated[batch_id] = amount
        remainder -= amount
      end

      allocated
    end
  end
end
