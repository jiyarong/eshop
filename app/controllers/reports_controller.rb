class ReportsController < ApplicationController
  helper_method :report_value

  def inventory
    @snapshots = Ec::InventorySnapshot.includes(:sku).order(:sku_code, :platform, :account_id)
    @totals = Ec::InventoryTotal.includes(:sku).order(:sku_code)
  end

  def skus
    @skus = Ec::Sku.order(:sku_code)
  end

  def costs
    @sku_costs = Ec::SkuCost.includes(:sku).order(:sku_code)
    @wb_costs = Ec::SkuPlatformCost.includes(:sku, :cost).where(platform: "wb").order(:sku_code, :delivery_mode, :company_type)
    @ozon_costs = Ec::SkuPlatformCost.includes(:sku, :cost).where(platform: "ozon").order(:sku_code, :delivery_mode, :company_type)
  end

  private

  def report_value(value)
    return "-" if value.nil? || value == ""
    return format("%.2f", value) if value.is_a?(Float) || value.is_a?(BigDecimal)

    value
  end
end
