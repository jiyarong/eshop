module Ec
  class PalletPlanSyncJob < ApplicationJob
    queue_as :default

    def perform(plan_id: nil)
      scope = Ec::PalletPlan.where(status: Ec::PalletPlans::OzonReconciler::SYNC_STATUSES)
        .where.not(supply_order_number: [nil, ""])
      scope = plan_id ? scope.where(id: plan_id) : scope.where.not(status: "closed")
      scope.includes(:store).to_a.group_by { |plan| plan.store.ozon_raw_account_id }.each do |account_id, plans|
        account = RawOzon::SellerAccount.find_by(id: account_id)
        next mark_errors(plans, :supply_mismatch) unless account
        sync = RawOzon::DailySync.new(account, days: 2)
        if plans.any? { |plan| plan.ozon_order_id.blank? }
          sync.sync_supply_orders
        else
          sync.sync_supply_orders(order_ids: plans.map(&:ozon_order_id).uniq)
        end
        plans.each { |plan| Ec::PalletPlans::OzonReconciler.new(plan: plan.reload).sync! }
      rescue StandardError => error
        Rails.logger.error("Pallet plan Ozon sync failed for account #{account_id}: #{error.class}")
        mark_errors(plans, :sync_failed)
      end
    end

    private

    def mark_errors(plans, key)
      message = Ec::PalletPlans::Error.new(key).message
      plans.each { |plan| plan.update!(sync_error: message) }
    end
  end
end
