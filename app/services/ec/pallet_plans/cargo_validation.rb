module Ec
  module PalletPlans
    class CargoValidation
      def initialize(plan:, drop_off: nil, drop_off_name: nil, warehouse: nil)
        @plan, @drop_off, @drop_off_name, @warehouse = plan, drop_off.to_h, drop_off_name, warehouse.to_h
      end

      def call
        cargoes = @plan.pallets.includes(items: :pallet_plan_item).to_a
        types = cargoes.map(&:cargo_type).uniq
        raise Error.new(:invalid_shipping_mode) if cargoes.empty? || !types.one? || !types.first.in?(%w[box pallet])
        boxes = types.first == "box"
        limit = boxes ? BoxPacking::MAX_BOXES : 40
        raise Error.new(:shipping_unavailable) if cargoes.size > limit

        cargoes.each do |cargo|
          if boxes
            weight = cargo.metrics.to_h["gross_weight"].to_d
            unless weight.positive? && weight <= BoxPacking::MAX_WEIGHT && cargo.items.one? && cargo.items.sole.boxes == 1
              raise Error.new(:shipping_unavailable)
            end
          else
            limits = PalletPacking::Rules::PROFILES.fetch(Ec::PalletPlans::Packing::PROFILE)
            height = cargo.metrics.to_h["height"].to_d
            weight = cargo.layout.to_h["weight"].to_d
            unless height.positive? && height <= limits.fetch(:height) && weight.positive? && weight <= limits.fetch(:weight)
              raise Error.new(:shipping_unavailable)
            end
          end
        end

        expected = @plan.items.pluck(:id, :boxes, :units).to_h { |id, cartons, units| [id, [cartons, units]] }
        actual = cargoes.flat_map(&:items).group_by(&:pallet_plan_item_id)
          .transform_values { |items| [items.sum(&:boxes), items.sum(&:units)] }
        raise Error.new(:shipping_unavailable) unless actual == expected

        point_info = if @drop_off.present?
          { type: @drop_off["warehouse_type"], name: @drop_off_name }
        elsif @warehouse.present?
          { type: "WAREHOUSE", name: @warehouse["name"] }
        else
          { type: "WAREHOUSE", name: nil }
        end
        point = { "DELIVERY_POINT" => "pvz", "ORDERS_RECEIVING_POINT" => "ppz", "SORTING_CENTER" => "sorting_center" }
          .fetch(point_info[:type], "warehouse")
        quote = PalletPacking::ShippingModeAdvisor.new(box_volumes_l: [1], pallet_volumes_l: Array.new(boxes ? 1 : cargoes.size, 1),
          box_count: boxes ? cargoes.size : expected.values.sum(&:first), point_type: point,
          point_name: point_info[:name]).call
        raise Error.new(:shipping_unavailable) unless quote.fetch(types.first.to_sym)[:available]
        true
      end
    end
  end
end
