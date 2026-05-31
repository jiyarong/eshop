namespace :cost do
  desc "将 ec_sku_costs 和 ec_sku_platform_costs 写入 Google Sheet（sku_cost / platform_cost 两个 Tab）"
  task write_sheet: :environment do
    require_relative '../../app/services/google_sheets/cost_sheet_write_service'
    GoogleSheets::CostSheetWriteService.new.call
  end
end
