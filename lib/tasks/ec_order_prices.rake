namespace :ec do
  namespace :order_prices do
    desc "Backfill WB order item commission base / buyer paid prices from raw Statistics orders (dry run unless APPLY=1)"
    task backfill_wb: :environment do
      apply = ENV["APPLY"] == "1"
      result = Ec::OrderImport::WbPriceBackfill.call(
        dry_run: !apply,
        clear_unmatched: ENV["KEEP_UNMATCHED"] != "1"
      )
      puts "#{apply ? 'applied' : 'dry run'}: #{result.inspect}"
      puts "re-run with APPLY=1 to write" unless apply
    end
  end
end
