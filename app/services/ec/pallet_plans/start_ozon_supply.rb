module Ec
  module PalletPlans
    class StartOzonSupply
      def self.verifier
        Rails.application.message_verifier("pallet_calculator_ozon_supply")
      end

      def initialize(user:, attributes:, calculation_token:)
        @user, @attributes, @token = user, attributes.to_h.stringify_keys, calculation_token
      end

      def call
        snapshot = self.class.verifier.verified(@token, purpose: "supply") if @token.present?
        raise Error.new(:invalid_calculation) unless snapshot && snapshot["user_id"] == @user.id
        request_key = snapshot.fetch("request_key")
        existing = Ec::OzonSupplySubmission.find_by(request_key: request_key)
        if existing
          raise Error.new(:invalid_calculation) unless existing.pallet_plan.created_by_id == @user.id
          raise Error.new(:sku_unavailable) if existing.pallet_plan.items.where.not(sku_code: WeeklyProfitReports::AccessScope.new(@user).visible_skus.select(:sku_code)).exists?
          return existing
        end

        delivery = delivery_attributes
        Ec::OzonSupplySubmission.transaction do
          plan = Save.new(user: @user, attributes: snapshot.fetch("attributes").merge(
            "store_id" => @attributes["store_id"], "cluster_id" => @attributes["cluster_id"]
          )).call
          plan.with_lock do
            raise Error.new(:not_editable) unless plan.editable?
            raise Error.new(:sku_unavailable) if plan.items.where.not(sku_code: WeeklyProfitReports::AccessScope.new(@user).visible_skus.select(:sku_code)).exists?
            raise Error.new(:invalid_store) unless plan.store.is_active? && plan.store.ozon_raw_account_id.present?
            plan.create_ozon_supply_submission!(request_key: request_key, data: delivery)
          end
        end
      rescue ActiveRecord::RecordNotUnique
        Ec::OzonSupplySubmission.find_by!(request_key: request_key)
      end

      private

      def delivery_attributes
        type = @attributes.fetch("supply_type", "DIRECT")
        raise Error.new(:invalid_delivery) unless type.in?(%w[DIRECT CROSSDOCK])
        result = { "supply_type" => type }
        if type == "CROSSDOCK"
          id, kind = @attributes["drop_off"].to_s.split(":", 2)
          raise Error.new(:invalid_delivery) unless id.match?(/\A[1-9]\d*\z/) && kind.in?(%w[DELIVERY_POINT SORTING_CENTER CROSS_DOCK ORDERS_RECEIVING_POINT FULL_FILLMENT])
          result["drop_off"] = { "warehouse_id" => id.to_i, "warehouse_type" => kind }
        end
        result
      end
    end
  end
end
