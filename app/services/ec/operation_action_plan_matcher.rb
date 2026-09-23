module Ec
  class OperationActionPlanMatcher
    def self.call(action)
      matches = matching_operations(action)
      return if matches.empty?

      action.sku.with_lock do
        plan = action.sku.sku_operation_plans.latest.active.retained
          .where("created_at <= ?", action.operated_at)
          .order(created_at: :desc, id: :desc)
          .find { |candidate| matches.include?([candidate.target, candidate.operation]) }
        next unless plan

        plan.update!(status: :done, completed_at: action.operated_at)
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
        operations.map { |operation| [ "price", operation ] }
      when "sku_adv_on_off"
        [ [ "advertising", fields.dig("advertising_enabled", "to") ? "open" : "close" ] ] if fields.key?("advertising_enabled")
      when "sku_adv_budget"
        budget_change = %w[daily_budget weekly_budget].filter_map { |key| fields[key] }.first
        return [] unless budget_change

        operations = [ "modify" ]
        operations << "increase" if increased?(budget_change)
        operations.map { |operation| [ "advertising", operation ] }
      when "listing_content", "listing_specification"
        targets = []
        targets << [ "listing_image", "modify" ] if fields.key?("images")
        targets << [ "listing_attribute", "modify" ] if fields.except("images").any?
        targets
      end || []
    end

    def self.increased?(change)
      from = BigDecimal(change.fetch("from").to_s, exception: false)
      to = BigDecimal(change.fetch("to").to_s, exception: false)
      from && to && to > from
    end
    private_class_method :matching_operations, :increased?
  end
end
