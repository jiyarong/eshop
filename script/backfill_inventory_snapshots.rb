# frozen_string_literal: true

# Usage:
#   bin/rails runner script/backfill_inventory_snapshots.rb
#   FROM_DATE=2026-06-25 TO_DATE=2026-07-24 bin/rails runner script/backfill_inventory_snapshots.rb

to_date = ENV.fetch("TO_DATE", (Ec::Snapshot.current_date - 1).iso8601).then { |value| Date.iso8601(value) }
from_date = ENV.fetch("FROM_DATE", (to_date - 29.days).iso8601).then { |value| Date.iso8601(value) }

raise ArgumentError, "FROM_DATE must be on or before TO_DATE" if from_date > to_date

total_rows = 0
(from_date..to_date).each do |snapshot_date|
  row_count = Ec::SnapshotRunner.new(
    snapshot_date: snapshot_date,
    modules: [ Ec::InventorySnapshot ]
  ).run
  total_rows += row_count
  puts "#{snapshot_date}: #{row_count} inventory snapshots"
end

puts "Backfilled #{total_rows} inventory snapshots from #{from_date} through #{to_date}."
