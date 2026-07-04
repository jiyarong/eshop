namespace :inventory do
  desc "Write the inventory report list with dimensions and volume columns into Google Sheet tab Inventory With Vol"
  task write_with_vol_sheet: :environment do
    require_relative "../../app/services/google_sheets/inventory_with_vol_sheet_service"
    result = GoogleSheets::InventoryWithVolSheetService.new.call
    puts "✓ Wrote #{result[:sku_count]} rows to #{result[:tab]}"
  end
end
