module PalletWorkbenchesHelper
  def pallet_workbench_initial_items
    return [] unless @plan

    @plan.calculation.fetch("items", []).map { |item| item.merge("quantity" => @plan.items.find { |row| row.sku_code == item["sku_code"] }&.boxes) }
  end

  def pallet_workbench_initial_allocations
    return [] unless @plan

    calculation = @plan.calculation.deep_symbolize_keys
    Array(calculation[:pallets]).map do |pallet|
      { items: pallet[:zones].group_by { |zone| calculation[:items][zone[:item_index]][:sku_code] }.map do |sku_code, zones|
        { sku_code: sku_code, quantity: zones.sum { |zone| zone[:count] } }
      end }
    end
  end

  def pallet_workbench_status(plan)
    content_tag(:span, t("pallet_workbench.statuses.#{plan.status}"), class: "ozon-warehouse-status #{%w[closed cancelled].include?(plan.status) ? '' : 'ozon-warehouse-status--shortage'}")
  end
end
