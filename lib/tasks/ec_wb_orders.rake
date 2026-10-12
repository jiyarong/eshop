namespace :ec do
  namespace :wb_orders do
    desc "Import WB statistics orders that have no order yet and no marketplace order (dry run unless APPLY=1)"
    task import_unlinked_stats: :environment do
      apply = ENV["APPLY"] == "1"
      count = Ec::OrderImport::Wb.new.import_unlinked_stats_only_orders(dry_run: !apply)
      puts "#{apply ? 'imported' : 'would import'}: #{count}"
      puts "re-run with APPLY=1 to write" unless apply
    end
  end
end
