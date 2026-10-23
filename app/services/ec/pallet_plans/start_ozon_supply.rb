module Ec
  module PalletPlans
    class StartOzonSupply
      def self.verifier
        Rails.application.message_verifier("pallet_calculator_ozon_supply")
      end

      def self.drop_off_verifier
        Rails.application.message_verifier("pallet_drop_off_selection")
      end

      def initialize(user:, attributes:, calculation_token: nil, plan: nil)
        @user, @attributes, @token, @plan = user, attributes.to_h.stringify_keys, calculation_token, plan
      end

      def call
        return start_saved_plan if @plan

        snapshot = self.class.verifier.verified(@token, purpose: "supply") if @token.present?
        raise Error.new(:invalid_calculation) unless snapshot && snapshot["user_id"] == @user.id
        request_key = snapshot.fetch("request_key")
        existing = Ec::OzonSupplySubmission.find_by(request_key: request_key)
        if existing
          raise Error.new(:invalid_calculation) unless existing.pallet_plan.created_by_id == @user.id
          raise Error.new(:sku_unavailable) if existing.pallet_plan.items.where.not(sku_code: WeeklyProfitReports::AccessScope.new(@user).visible_skus.select(:sku_code)).exists?
          return existing
        end

        Ec::OzonSupplySubmission.transaction do
          plan = Save.new(user: @user, attributes: snapshot.fetch("attributes").merge(
            "store_id" => @attributes["store_id"], "cluster_id" => @attributes["cluster_id"]
          )).call
          plan.with_lock do
            raise Error.new(:not_editable) unless plan.editable?
            raise Error.new(:sku_unavailable) if plan.items.where.not(sku_code: WeeklyProfitReports::AccessScope.new(@user).visible_skus.select(:sku_code)).exists?
            raise Error.new(:invalid_store) unless plan.store.is_active? && plan.store.ozon_raw_account_id.present?
            delivery = delivery_attributes(plan: plan)
            CargoValidation.new(plan: plan, drop_off: delivery.fetch("drop_off", {}),
              drop_off_name: delivery["drop_off_name"]).call
            plan.create_ozon_supply_submission!(request_key: request_key, data: delivery.merge("requested_by_id" => @user.id))
          end
        end
      rescue ActiveRecord::RecordNotUnique
        Ec::OzonSupplySubmission.find_by!(request_key: request_key)
      end

      private

      def start_saved_plan
        @plan.with_lock do
          raise Error.new(:sku_unavailable) if @plan.items.where.not(sku_code: WeeklyProfitReports::AccessScope.new(@user).visible_skus.select(:sku_code)).exists?
          raise Error.new(:not_editable) unless @plan.status.in?(Ec::PalletPlan::EDITABLE_STATUSES) && @plan.ozon_order_id.blank?
          existing = @plan.ozon_supply_submission
          next existing if existing && existing.state != "cancelled"
          raise Error.new(:stale_plan) unless @plan.lock_version.to_s == @attributes["lock_version"].to_s
          raise Error.new(:invalid_store) unless @plan.store.is_active? && @plan.store.ozon_raw_account_id.present?

          Build.new(user: @user, attributes: saved_plan_attributes, existing_plan: @plan).call
          delivery = delivery_attributes(plan: @plan)
          CargoValidation.new(plan: @plan, drop_off: delivery.fetch("drop_off", {}), drop_off_name: delivery["drop_off_name"]).call
          existing&.destroy!
          @plan.create_ozon_supply_submission!(request_key: SecureRandom.uuid, data: delivery.merge("requested_by_id" => @user.id))
        end
      end

      def saved_plan_attributes
        items_by_id = @plan.items.index_by(&:id)
        cargoes = @plan.pallets.includes(items: :pallet_plan_item).to_a
        allocations = cargoes.select { |pallet| pallet.cargo_type == "pallet" }.map do |pallet|
          rows = pallet.items.group_by(&:pallet_plan_item_id).map do |id, items|
            { sku_code: items_by_id.fetch(id).sku_code, quantity: items.sum(&:boxes) }
          end
          { items: rows }
        end
        {
          store_id: @plan.store_id, cluster_id: @plan.macrolocal_cluster_id,
          from_date: @plan.from_date, to_date: @plan.to_date, target_days: @plan.target_days, time_zone: @plan.time_zone,
          packing_mode: "multiple", settings: @plan.settings,
          shipping_mode: @plan.calculation.fetch("shipping_mode", "pallet"),
          shipping: @plan.calculation.fetch("shipping", {}).slice("supply_receiving_zone_key", "point_type", "point_name", "shipping_date"),
          items: @plan.items.map do |item|
            box_quantity = cargoes.select { |cargo| cargo.cargo_type == "box" }
              .sum { |cargo| cargo.items.select { |row| row.pallet_plan_item_id == item.id }.sum(&:boxes) }
            item.packaging.merge("sku_code" => item.sku_code, "quantity" => item.boxes, "box_quantity" => box_quantity)
          end,
          allocations: allocations
        }
      end

      def delivery_attributes(plan:)
        type = @attributes.fetch("supply_type", "DIRECT")
        raise Error.new(:invalid_delivery) unless type.in?(%w[DIRECT CROSSDOCK])
        result = { "supply_type" => type }
        if type == "CROSSDOCK"
          selection = self.class.drop_off_verifier.verified(@attributes["drop_off"], purpose: "drop-off") if @attributes["drop_off"].present?
          account_id = plan.store.ozon_raw_account_id
          unless selection && selection["account_id"].to_i == account_id.to_i &&
              selection["warehouse_id"].to_s.match?(/\A[1-9]\d*\z/) &&
              selection["warehouse_type"].in?(%w[DELIVERY_POINT SORTING_CENTER CROSS_DOCK ORDERS_RECEIVING_POINT FULL_FILLMENT])
            raise Error.new(:invalid_delivery)
          end
          result["drop_off"] = { "warehouse_id" => selection.fetch("warehouse_id").to_i,
            "warehouse_type" => selection.fetch("warehouse_type") }
          result["drop_off_name"] = selection["name"].to_s
        end
        result
      rescue ActiveSupport::MessageVerifier::InvalidSignature, KeyError
        raise Error.new(:invalid_delivery)
      end
    end
  end
end
