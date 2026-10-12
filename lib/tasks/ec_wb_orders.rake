namespace :ec do
  namespace :wb_orders do
    desc "Import WB statistics orders that have no order yet and no marketplace order (dry run unless APPLY=1)"
    task import_unlinked_stats: :environment do
      apply = ENV["APPLY"] == "1"
      importer = Ec::OrderImport::Wb.new
      count = importer.import_unlinked_stats_only_orders(dry_run: !apply)
      puts "#{apply ? 'imported' : 'would import'}: #{count}"
      puts "skipped (g_number covered by a marketplace order): #{importer.count_unlinked_stats_covered_only_by_g_number}"
      puts "re-run with APPLY=1 to write" unless apply
    end
  end
end
