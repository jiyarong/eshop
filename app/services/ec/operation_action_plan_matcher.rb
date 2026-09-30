module Ec
  class OperationActionPlanMatcher
    IMAGE_FIELDS = %w[images primary_image images360 color_image].freeze

    def self.call(action)
      return if action.plan_id.present?

      matches = matching_operations(action)
      return if matches.empty?

      action.sku.with_lock do
        action_date = action.operated_at.in_time_zone(Ec::SkuOperationPlan::TIME_ZONE).to_date
        plan = action.sku.sku_operation_plans
          .where(lifecycle_status: "active")
          .where("planning_period_start <= ? AND execution_deadline >= ?", action_date, action_date)
          .where("created_at <= ?", action.operated_at)
          .order(is_latest: :desc, created_at: :desc, id: :desc)
          .find do |candidate|
            matches.include?([candidate.target, candidate.operation]) && scope_matches?(candidate, action)
          end
        next unless plan

        plan.update!(status: :done, execution_status: :executed, completed_at: action.operated_at)
        action.update!(plan: plan)
      end
    end

    def self.matching_operations(action)
      fields = action.diff_result.fetch("fields", {})
      case action.operation_type
      when "listing_pricing"
        price_change = %w[customer_price final_price marketing_price price].filter_map { |key| fields[key] }.first
        return [] unless price_change

        operations = [ "modify" ]
        operations << "increase" if increased?(price_change)
        operations << "decrease" if decreased?(price_change)
        operations.map { |operation| [ "price", operation ] }
      when "sku_adv_on_off"
        enabled = fields.dig("advertising_enabled", "to")
        [ [ "advertising", enabled ? "open" : "close" ] ] if enabled == true || enabled == false
      when "sku_adv_budget"
        budget_change = %w[daily_budget weekly_budget].filter_map { |key| fields[key] }.first
        return [] unless budget_change

        operations = [ "modify" ]
        operations << "increase" if increased?(budget_change)
        operations << "decrease" if decreased?(budget_change)
        operations.map { |operation| [ "advertising", operation ] }
      when "supply_order"
        quantity_change = fields["purchased_quantity"]
        return [ [ "replenishment", "increase" ] ] if quantity_change && increased?(quantity_change)

        status = fields.dig("supply_order_status", "to")
        shipped_statuses = %w[planned unloading_allowed accepting accepted unloaded_at_gate
          READY_TO_SUPPLY ACCEPTED_AT_SUPPLY_WAREHOUSE IN_TRANSIT ACCEPTANCE_AT_STORAGE_WAREHOUSE COMPLETED]
        return [] unless status.in?(shipped_statuses) && action.diff_result.dig("supply_order", "sku_quantity").to_i.positive?

        [ [ "warehouse_distribution", "increase" ], [ "warehouse_distribution", "modify" ] ]
      when "sku_inbound_change"
        quantity_change = fields["platform_inbound_quantity"] || fields["quantity"]
        return [] unless quantity_change

        return [] unless increased?(quantity_change)

        [ [ "warehouse_distribution", "increase" ], [ "warehouse_distribution", "modify" ] ]
      when "listing_content", "listing_specification"
        targets = []
        targets << [ "listing_image", "modify" ] if fields.keys.intersect?(IMAGE_FIELDS)
        targets << [ "listing_attribute", "modify" ] if fields.except(*IMAGE_FIELDS).any?
        targets
      end || []
    end

    def self.scope_matches?(plan, action)
      case plan.scope
      when "LISTING"
        plan.scope_id == action.ec_sku_product_id.to_s
      when "SKU"
        plan.scope_id == action.sku.sku_code
      else
        plan.scope.blank?
      end
    end

    def self.increased?(change)
      from = BigDecimal(change.fetch("from").to_s, exception: false)
      to = BigDecimal(change.fetch("to").to_s, exception: false)
      from && to && to > from
    end

    def self.decreased?(change)
      from = BigDecimal(change.fetch("from").to_s, exception: false)
      to = BigDecimal(change.fetch("to").to_s, exception: false)
      from && to && to < from
    end
    private_class_method :matching_operations, :scope_matches?, :increased?, :decreased?
  end
end
