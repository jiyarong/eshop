module Ec
  module PalletPlans
    class OzonReconciler
      DEPARTED_STATES = %w[ACCEPTED_AT_SUPPLY_WAREHOUSE IN_TRANSIT ACCEPTANCE_AT_STORAGE_WAREHOUSE REPORTS_CONFIRMATION_AWAITING REPORT_REJECTED].freeze
      READY_STATES = %w[DATA_FILLING READY_TO_SUPPLY].freeze
      COMMITTED_STATUSES = Ec::PalletPlan::COMMITTED_STATUSES
      SYNC_STATUSES = %w[draft reserved packing packed dispatched closed].freeze

      def self.sync_for(account_id:, order_ids:)
        orders = RawOzon::SupplyOrder.where(account_id: account_id, supply_order_id: order_ids.map(&:to_s))
        numbers = orders.filter_map { |order| order.raw_json.to_h["order_number"].presence }
        plans = Ec::PalletPlan.joins(:store).where(ec_stores: { ozon_raw_account_id: account_id })
          .where(status: SYNC_STATUSES)
        plans.where(ozon_order_id: order_ids.map(&:to_s)).or(plans.where(supply_order_number: numbers)).find_each do |plan|
          reconciler = new(plan: plan)
          plan.ozon_order_id.present? ? reconciler.sync! : reconciler.bind!(plan.supply_order_number)
        rescue Ec::PalletPlans::Error => error
          plan.update!(sync_error: error.message)
        end
      end

      def initialize(plan:)
        @plan = plan
      end

      def bind!(number, enqueue: true)
        fail_input(:invalid_status) unless @plan.status.in?(SYNC_STATUSES)
        number = number.to_s.strip
        fail_input(:binding_number) if number.blank?
        order = account_orders.where(supply_order_id: number)
          .or(account_orders.where("raw_json ->> 'order_number' = ?", number)).first
        unless order
          @plan.with_lock do
            fail_input(:supply_mismatch) if @plan.ozon_order_id.present?
            @plan.update!(supply_order_number: number, sync_error: Error.new(:supply_pending).message)
          end
          Ec::PalletPlanSyncJob.perform_later(plan_id: @plan.id) if enqueue
          return @plan
        end
        @plan.with_lock do
          fail_input(:supply_mismatch) if @plan.ozon_order_id.present? && @plan.ozon_order_id != order.supply_order_id
          apply_order!(order, binding: true)
        end
        @plan
      rescue Error => error
        @plan.update!(sync_error: error.message)
        raise
      end

      def sync!
        return bind!(@plan.supply_order_number, enqueue: false) if @plan.ozon_order_id.blank?
        @plan.with_lock do
          order = account_orders.find_by(supply_order_id: @plan.ozon_order_id)
          fail_input(:supply_pending) unless order
          apply_order!(order, binding: false)
        end
        @plan
      rescue Error => error
        @plan.update!(sync_error: error.message)
        @plan
      end

      private

      def account_orders
        account_id = @plan.store.ozon_raw_account_id
        fail_input(:supply_mismatch) unless @plan.store.ozon? && account_id.present?
        RawOzon::SupplyOrder.where(account_id: account_id)
      end

      def apply_order!(order, binding:)
        state = order.status.to_s
        fail_input(:supply_unknown_status) unless (READY_STATES + DEPARTED_STATES + %w[COMPLETED CANCELLED REJECTED_AT_SUPPLY_WAREHOUSE OVERDUE]).include?(state)
        if state == "CANCELLED" && !binding
          apply_cancellation!(order)
          return
        end
        fail_input(:supply_review_required) if %w[REJECTED_AT_SUPPLY_WAREHOUSE OVERDUE CANCELLED].include?(state)
        evidence, pallet_destinations = matching_evidence!(order)
        if dispatched? && READY_STATES.include?(state) && evidence.values.all? { |item| READY_STATES.include?(item[:state]) }
          fail_input(:supply_status_regressed)
        end
        previous = @plan.platform_snapshot.to_h.fetch("items", {})
        evidence.each do |sku_code, item|
          old = previous[sku_code].to_h
          if old.present? && [old["supply_id"].to_s, old["warehouse_id"].to_s] != [item[:supply_id].to_s, item[:warehouse_id].to_s]
            fail_input(:supply_warehouse_changed)
          end
        end
        pallet_destinations.each do |pallet, destination|
          pallet.update!(ozon_supply_id: destination[:supply_id], storage_warehouse_id: destination[:warehouse_id])
        end
        attributes = {
          ozon_order_id: order.supply_order_id,
          supply_order_number: order.raw_json.to_h["order_number"].presence || @plan.supply_order_number.presence || order.supply_order_id,
          platform_status: state, platform_synced_at: order.synced_at || Time.current, sync_error: nil,
          platform_snapshot: {
            order_id: order.supply_order_id, order_number: order.raw_json.to_h["order_number"], state: state,
            order_state_updated_at: order.raw_json.to_h["state_updated_date"],
            synced_at: order.synced_at&.iso8601, items: evidence
          }
        }
        if COMMITTED_STATUSES.include?(@plan.status)
          if state == "COMPLETED" && evidence.values.all? { |item| item[:state] == "COMPLETED" }
            attributes.merge!(status: "closed", dispatched_at: @plan.dispatched_at || Time.current, closed_at: @plan.closed_at || Time.current)
          elsif @plan.status != "closed" && (DEPARTED_STATES.include?(state) || evidence.values.any? { |item| DEPARTED_STATES.include?(item[:state]) || item[:state] == "COMPLETED" })
            attributes.merge!(status: "dispatched", dispatched_at: @plan.dispatched_at || Time.current)
          end
        end
        @plan.update!(attributes)
      end

      def matching_evidence!(order)
        plan_items = @plan.items.to_a
        fail_input(:supply_mismatch) if plan_items.empty? || plan_items.any? { |item| item.platform_sku_id.blank? }
        expected = plan_items.each_with_object(Hash.new(0)) { |item, totals| totals[item.platform_sku_id.to_s] += item.units }
        rows = supply_report_rows(order)
        actual = rows.each_with_object(Hash.new(0)) { |item, totals| totals[item[:platform_item_id].to_s] += item[:quantity].to_i }
        fail_input(:supply_mismatch) unless actual == expected
        fail_input(:supply_cluster) if rows.any? { |item| item[:destination_cluster_id].to_s != @plan.macrolocal_cluster_id.to_s }
        rows_by_sku = rows.group_by { |item| item[:platform_item_id].to_s }
        fail_input(:supply_split) if rows_by_sku.values.any? { |items| items.map { |item| [item[:supply_id], item[:destination_warehouse_id]] }.uniq.size > 1 }
        evidence = plan_items.to_h do |item|
          row = rows_by_sku.fetch(item.platform_sku_id.to_s).first
          fail_input(:supply_pallet) if row[:supply_id].blank? || row[:destination_warehouse_id].blank?
          [item.sku_code, {
            platform_sku_id: item.platform_sku_id.to_s, quantity: item.units, state: row[:status].presence || order.status,
            supply_id: row[:supply_id].to_s, warehouse_id: row[:destination_warehouse_id],
            cluster_id: row[:destination_cluster_id]
          }]
        end
        destinations = @plan.pallets.includes(items: :pallet_plan_item).map do |pallet|
          targets = pallet.items.map { |item| evidence.fetch(item.pallet_plan_item.sku_code).slice(:supply_id, :warehouse_id) }.uniq
          fail_input(:supply_pallet) unless targets.one?
          [pallet, targets.first]
        end
        [evidence, destinations]
      end

      def supply_report_rows(order)
        SupplyOrderReports::ReportQuery.new(
          params: {
            store_ref: "ozon:#{@plan.store.ozon_raw_account_id}",
            supply_order_id: order.supply_order_id
          }
        ).ozon_reconciliation_rows
      end

      def apply_cancellation!(order)
        if dispatched?
          @plan.update!(platform_status: order.status, platform_synced_at: order.synced_at || Time.current,
            sync_error: Error.new(:supply_cancelled_after_dispatch).message)
        else
          @plan.update!(status: "cancelled", platform_status: order.status,
            platform_synced_at: order.synced_at || Time.current, sync_error: nil)
        end
      end

      def dispatched?
        @plan.dispatched_at.present? || %w[dispatched closed].include?(@plan.status) ||
          @plan.platform_snapshot.to_h.fetch("items", {}).values.any? { |item| (DEPARTED_STATES + ["COMPLETED"]).include?(item["state"]) }
      end

      def fail_input(key, **details)
        raise Error.new(key, **details)
      end
    end
  end
end
