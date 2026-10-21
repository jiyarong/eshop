module Ec
  module PalletPlans
    class OzonSupplyActions
      def initialize(submission:)
        @submission = submission
      end

      def select_warehouse!(warehouse_id)
        change do
          raise Error.new(:invalid_status) unless @submission.warehouse_selectable?
          check_expiry!
          warehouse = @submission.data.fetch("warehouses", []).find { |row| row.dig("storage_warehouse", "warehouse_id").to_s == warehouse_id.to_s }
          raise Error.new(:invalid_warehouse) unless warehouse
          @submission.update!(state: "loading_timeslots", poll_attempts: 0, last_error: nil,
            data: @submission.data.merge("warehouse" => warehouse, "timeslots" => [], "order_attempted" => false, "order_failed" => false))
        end
      end

      def submit!(timeslot_index)
        change do
          require_state!("timeslot_required")
          check_expiry!
          raise Error.new(:invalid_timeslot) unless timeslot_index.to_s.match?(/\A\d+\z/)
          timeslot = @submission.data.fetch("timeslots", [])[timeslot_index.to_i]
          raise Error.new(:invalid_timeslot) unless timeslot
          plan = @submission.pallet_plan
          raise Error.new(:invalid_status) unless plan.status.in?(Ec::PalletPlan::EDITABLE_STATUSES) && plan.ozon_order_id.blank?
          CargoValidation.new(plan: plan, drop_off: @submission.data["drop_off"],
            drop_off_name: @submission.data["drop_off_name"],
            warehouse: @submission.data.dig("warehouse", "storage_warehouse")).call
          availability = Availability.new(sku_codes: plan.items.map(&:sku_code), excluding_plan_id: plan.id, store_id: plan.store_id).call
          plan.items.each do |item|
            raise Error.new(:insufficient_stock, sku: item.sku_code) if availability.fetch(item.sku_code).fetch(:available_quantity) < item.units
          end
          plan.with_lock do
            plan.update!(status: "reserved", confirmed_at: Time.current) if plan.status == "draft"
            @submission.update!(state: "order_queued", last_error: nil, poll_attempts: 0,
              data: @submission.data.merge("timeslot" => timeslot))
          end
        end
      end

      def retry!
        change do
          raise Error.new(:invalid_status) unless @submission.retryable?
          @submission.update!(state: @submission.data.fetch("resume_state"), last_error: nil, poll_attempts: 0)
        end
      end

      def cancel!
        change do
          raise Error.new(:invalid_status) unless @submission.cancellable?
          @submission.update!(state: "cancelled")
        end
      end

      private

      def change
        SyncRunLock.with_lock(@submission.lock_name, wait: true) do
          @submission.reload
          yield
        end
        @submission
      end

      def require_state!(*states)
        raise Error.new(:invalid_status) unless @submission.state.in?(states)
      end

      def check_expiry!
        raise Error.new(:draft_expired) if @submission.draft_expired?
      end
    end
  end
end
