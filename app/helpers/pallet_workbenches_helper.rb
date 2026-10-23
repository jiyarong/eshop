module PalletWorkbenchesHelper
  def pallet_workbench_initial_items
    return [] unless @plan

    plan_items = @plan.items.index_by(&:sku_code)
    box_quantities = @plan.pallets.joins(:items).where(cargo_type: "box").reorder(nil)
      .group("ec_pallet_items.pallet_plan_item_id").sum("ec_pallet_items.boxes")
    @plan.calculation.fetch("items", []).map do |item|
      plan_item = plan_items[item["sku_code"]]
      item.merge("quantity" => plan_item&.boxes, "box_quantity" => box_quantities.fetch(plan_item&.id, 0))
    end
  end

  def pallet_workbench_initial_allocations
    return [] unless @plan

    calculation = @plan.calculation.deep_symbolize_keys
    Array(calculation[:pallets]).reject { |pallet| pallet[:cargo_type] == "box" }.map do |pallet|
      { items: pallet[:zones].group_by { |zone| calculation[:items][zone[:item_index]][:sku_code] }.map do |sku_code, zones|
        { sku_code: sku_code, quantity: zones.sum { |zone| zone[:count] } }
      end }
    end
  end

  def pallet_workbench_status(plan)
    content_tag(:span, t("pallet_workbench.statuses.#{plan.status}"), class: "ozon-warehouse-status #{%w[closed cancelled].include?(plan.status) ? '' : 'ozon-warehouse-status--shortage'}")
  end
end
