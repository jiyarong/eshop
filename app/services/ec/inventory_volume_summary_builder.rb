module Ec
  class InventoryVolumeSummaryBuilder
    SUMMARY_BUCKETS = {
      pending_stock_volume_m3: :incoming_quantity,
      book_available_stock_volume_m3: :book_stock,
      platform_inbound_stock_volume_m3: :platform_inbound_stock,
      platform_stock_volume_m3: :platform_stock,
      overseas_available_stock_volume_m3: :available_stock
    }.freeze

    LITERS_PER_CUBIC_METER = BigDecimal("1000")

    def self.call(rows)
      new(rows).call
    end

    def initialize(rows)
      @rows = Array(rows)
    end

    def call
      SUMMARY_BUCKETS.keys.index_with { BigDecimal("0") }.tap do |summary|
        rows.each do |row|
          unit_volume_l = row[:unit_volume_l]
          next if unit_volume_l.blank?

          unit_volume_l = unit_volume_l.to_d
          next unless unit_volume_l.positive?

          SUMMARY_BUCKETS.each do |summary_key, quantity_key|
            contribution = row[quantity_key].to_d * unit_volume_l / LITERS_PER_CUBIC_METER
            next unless contribution.positive?

            summary[summary_key] += contribution
          end
        end
      end
    end

    private

    attr_reader :rows
  end
end
