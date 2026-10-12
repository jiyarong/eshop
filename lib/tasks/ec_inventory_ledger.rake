require "csv"

namespace :ec do
  namespace :inventory do
    desc "Compare legacy book stock with the book ledger for every SKU (read only), writes tmp/ledger_diff_*.csv"
    task ledger_diff: :environment do
      rows = Ec::Inventory::LedgerDiff.call(sku_codes: Ec::Sku.order(:sku_code).pluck(:sku_code))
      path = Rails.root.join("tmp", "ledger_diff_#{Time.current.strftime('%Y%m%d%H%M')}.csv")
      CSV.open(path, "w") do |csv|
        csv << %w[sku_code legacy ledger diff stale_open in_transit at_platform unsellable]
        rows.each { |row| csv << row.values_at(:sku_code, :legacy, :ledger, :diff, :stale_open, :in_transit, :at_platform, :unsellable) }
      end
      changed = rows.count { |row| row[:diff] != 0 }
      puts "skus=#{rows.size} changed=#{changed} sum_diff=#{rows.sum { |row| row[:diff] }} csv=#{path}"
      puts "unattributed (top 10): #{Ec::Inventory::BookLedger.unattributed.first(10).inspect}"
    end
  end
end
