module Ec
  module PalletPlans
    class Save
      def initialize(user:, attributes:, plan: nil)
        @user, @attributes, @plan = user, attributes, plan
      end

      def call
        built = Build.new(user: @user, attributes: @attributes, existing_plan: @plan).call
        plan = @plan || Ec::PalletPlan.new(created_by: @user, store: built[:store])
        plan.with_lock do
          raise Error.new(:not_editable) if @plan && !plan.editable?
          plan.assign_attributes(
            store: built[:store], macrolocal_cluster_id: built[:cluster].macrolocal_cluster_id, cluster_name: built[:cluster].cluster_name,
            from_date: built[:from_date], to_date: built[:to_date], target_days: built[:target_days], time_zone: built[:time_zone],
            settings: built[:result][:settings], calculation: built[:result], status: plan.status.presence || "draft"
          )
          plan.save!
          plan.pallets.destroy_all
          plan.items.destroy_all
          product_by_code = Ec::SkuProduct.where(id: built[:items].filter_map { |item| item[:sku_product_id] }).index_by(&:id)
            plan_items = built[:items].to_h { |item| [item[:sku_code], plan.items.create!(sku_code: item[:sku_code], sku_product: product_by_code.fetch(item[:sku_product_id]), platform_sku_id: product_by_code.fetch(item[:sku_product_id]).platform_sku_id.to_s, boxes: item[:quantity], pcs: item[:pcs].to_i, units: item[:quantity].to_i * item[:pcs].to_i, packaging: item.slice(:length, :width, :height, :weight, :pcs, :unit_volume_l, :ozon_size_category), shortage: 0)] }
          built[:result][:pallets].each_with_index do |pallet, index|
            record = plan.pallets.create!(position: index + 1, cargo_type: built[:result][:shipping_mode], layout: pallet, metrics: pallet.slice(:height, :gross_weight, :cargo_l, :boxes, :units))
            pallet[:zones].each do |zone|
              item = built[:result][:items][zone[:item_index]]; plan_item = plan_items.fetch(item[:sku_code])
              record.items.create!(pallet_plan_item: plan_item, boxes: zone[:count], units: zone[:count].to_i * plan_item.pcs, layout: zone)
            end
          end
        end
        plan
      rescue ActiveRecord::StaleObjectError
        raise Error.new(:stale_plan)
      end
    end
  end
end
