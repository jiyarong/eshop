# Captures and compares the physical stocktake numbers of every SKU, so a refactor of the order status model
# can be checked against the numbers recorded before it.
#
#   bin/rails runner script/physical_stocktake_baseline.rb capture tmp/physical_stocktake_after.json
#   bin/rails runner script/physical_stocktake_baseline.rb compare BASELINE.json AFTER.json
#
# `capture` is read-only. `compare` only reads the two files and prints the SKUs whose summary numbers differ.
require "json"

module PhysicalStocktakeBaseline
  SUMMARY_KEYS = %i[
    expected_physical_stock received_quantity physical_stocktake_adjustment_quantity
    fbs_departed_quantity fbs_not_departed_quantity fbs_order_quantity
    platform_supply_departed_quantity wb_supply_departed_quantity ozon_supply_departed_quantity
    wb_supply_reconciliation_quantity pending_supply_quantity
    seller_received_return_quantity ozon_seller_received_removal_quantity removal_to_seller_quantity
  ].freeze
  FBS_CELL_KEYS = %i[business_status return_business_status quantity kind].freeze

  module_function

  def capture(path)
    skus = Ec::Sku.order(:sku_code).to_a
    rows = skus.each_with_index.map do |sku, index|
      warn "#{index + 1}/#{skus.size} #{sku.sku_code}" if ((index + 1) % 25).zero?
      capture_sku(sku)
    end

    payload = {
      meta: meta(skus.size),
      skus: rows.to_h { |row| [ row[:sku_code], row.except(:sku_code) ] }
    }
    File.write(path, JSON.pretty_generate(payload))
    puts "wrote #{path} (#{rows.size} skus)"
  end

  def capture_sku(sku)
    overview = sku.inventory_overview
    result = Ec::InventoryPhysicalReconciliationQuery.new(sku, overview: overview).call

    {
      sku_code: sku.sku_code,
      summary: result[:summary].slice(*SUMMARY_KEYS),
      fbs_matrix: result[:fbs_matrix][:cells].map { |cell| cell.slice(*FBS_CELL_KEYS) },
      supply_row_count: result[:supply_pagination][:total_count],
      return_row_count: result[:return_pagination][:total_count],
      removal_row_count: result[:removal_rows].size
    }
  rescue StandardError => e
    { sku_code: sku.sku_code, error: "#{e.class}: #{e.message}" }
  end

  def meta(sku_count)
    connection = ActiveRecord::Base.connection
    {
      captured_at: Time.current.iso8601,
      database: connection.current_database,
      git_head: `git rev-parse HEAD`.strip,
      git_dirty_files: `git status --porcelain`.lines.size,
      sku_count: sku_count,
      ec_orders: connection.select_value("select count(*) from ec_orders").to_i,
      ec_order_fulfillments: connection.select_value("select count(*) from ec_order_fulfillments").to_i,
      ec_returns: connection.select_value("select count(*) from ec_returns").to_i,
      latest_ordered_at: connection.select_value("select max(ordered_at) from ec_orders")&.to_s
    }
  end

  def compare(baseline_path, after_path)
    baseline = JSON.parse(File.read(baseline_path))
    after = JSON.parse(File.read(after_path))
    puts "baseline: #{baseline['meta'].slice('captured_at', 'git_head', 'ec_orders', 'ec_returns', 'latest_ordered_at')}"
    puts "after:    #{after['meta'].slice('captured_at', 'git_head', 'ec_orders', 'ec_returns', 'latest_ordered_at')}"
    if baseline["meta"].values_at("ec_orders", "ec_returns") != after["meta"].values_at("ec_orders", "ec_returns")
      puts "WARNING: order/return counts differ, the database was not the same; differences below may be data, not code"
    end

    differing = 0
    (baseline["skus"].keys | after["skus"].keys).sort.each do |sku_code|
      before_row = baseline["skus"][sku_code]
      after_row = after["skus"][sku_code]
      unless before_row && after_row
        puts "#{sku_code}: only in #{before_row ? 'baseline' : 'after'}"
        differing += 1
        next
      end

      changes = SUMMARY_KEYS.filter_map do |key|
        before_value = before_row.dig("summary", key.to_s)
        after_value = after_row.dig("summary", key.to_s)
        "#{key} #{before_value} -> #{after_value}" if before_value != after_value
      end
      next if changes.empty?

      differing += 1
      puts "#{sku_code}: #{changes.join(', ')}"
    end
    puts "#{differing} of #{(baseline['skus'].keys | after['skus'].keys).size} skus differ"
  end
end

mode, first_path, second_path = ARGV
case mode
when "capture"
  abort "usage: capture OUT.json" unless first_path
  PhysicalStocktakeBaseline.capture(first_path)
when "compare"
  abort "usage: compare BASELINE.json AFTER.json" unless first_path && second_path
  PhysicalStocktakeBaseline.compare(first_path, second_path)
else
  abort "usage: capture OUT.json | compare BASELINE.json AFTER.json"
end
