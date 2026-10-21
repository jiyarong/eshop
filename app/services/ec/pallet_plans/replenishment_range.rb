module Ec
  module PalletPlans
    class ReplenishmentRange
      attr_reader :target_days, :min_days, :max_days, :fill_free_space

      def initialize(target_days: 28, min_days: nil, max_days: nil, fill_free_space: true)
        @target_days = Integer(target_days.presence || 28)
        @min_days = Integer(min_days.presence || @target_days)
        @max_days = Integer(max_days.presence || @target_days)
        @fill_free_space = ActiveModel::Type::Boolean.new.cast(fill_free_space) == true
        unless [@min_days, @target_days, @max_days].all? { |days| days.between?(1, 180) } &&
            @min_days <= @target_days && @target_days <= @max_days
          raise Error.new(:invalid_period)
        end
      rescue ArgumentError, TypeError
        raise Error.new(:invalid_period)
      end

      def to_h
        { min_days: min_days, target_days: target_days, max_days: max_days, fill_free_space: fill_free_space }
      end

      def boxes(daily_sales:, available:, inbound:, planned_quantity:, pcs:, allocatable:)
        return { min_boxes: 0, max_boxes: 0 } unless pcs.to_i.positive?

        stock = available.to_d + inbound.to_d + planned_quantity.to_d
        limit = [allocatable.to_i, 0].max / pcs.to_i
        minimum = [(daily_sales.to_d * min_days).ceil - stock, 0].max
        maximum = [daily_sales.to_d * max_days - stock, 0].max
        { min_boxes: [(minimum / pcs).ceil, limit].min,
          max_boxes: [(maximum / pcs).floor, limit].min }
      end
    end
  end
end
