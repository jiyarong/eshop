require "set"

module Ec
  # Applies a complete warehouse expense exactly once, at the SKU aggregate level.
  class OwnWarehouseProfitCosts
    def self.apply(rows:, summary:, from_date:, to_date:, sku_codes: [], sku_filter_active: false)
      weeks = (from_date.to_date..to_date.to_date).select(&:monday?)
      scope = Ec::OwnWarehouseSkuCostAllocation.current.where(week_start: weeks)
      periods = Ec::OwnWarehouseCostPeriod.published.where("effective_from <= ? AND (effective_to IS NULL OR effective_to >= ?)", to_date, from_date).to_a
      complete_weeks = scope.distinct.pluck(:own_warehouse_code, :week_start).to_set
      complete = periods.any? && weeks.all? do |week|
        expected = periods.select { |p| p.effective_from <= week + 6 && (p.effective_to.nil? || p.effective_to >= week) }.group_by(&:own_warehouse_code)
        expected.any? && expected.all? do |code, versions|
          complete_weeks.include?([code, week]) && (week..week + 6).all? { |day| versions.any? { |version| version.active_on?(day) } }
        end
      end
      scope = scope.where(sku_id: Ec::Sku.with_deleted.where(sku_code: sku_codes).select(:id)) if sku_filter_active
      costs = scope.joins(:sku).group("ec_skus.sku_code").sum(:total_cost)
      existing = rows.index_by { |row| row[:sku] }
      costs.each_key do |sku_code|
        next if existing.key?(sku_code)
        rows << { sku: sku_code, net_sales: 0, revenue: 0.to_d, ads: 0.to_d, goods_cost: 0.to_d, pre_tax: 0.to_d, tax: 0.to_d, after_tax: 0.to_d }
      end
      rows.each do |row|
        row[:own_warehouse_cost] = complete ? costs.fetch(row[:sku], 0.to_d).round(2) : nil
        row[:after_own_warehouse_cost] = complete ? (row[:after_tax].to_d - row[:own_warehouse_cost]).round(2) : nil
      end
      if summary
        summary[:total_sku_count] = rows.size
        summary[:total_own_warehouse_cost] = complete ? costs.values.sum.round(2) : nil
        summary[:total_after_own_warehouse_cost] = complete ? (summary[:total_after_tax].to_d - summary[:total_own_warehouse_cost]).round(2) : nil
        summary[:own_warehouse_cost_complete] = complete
      end
      rows
    end
  end
end
