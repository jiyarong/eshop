module Ec
  module Inventory
    # Single source of truth for book stock: how many units the seller owns and how much of it is sellable.
    # Does not look at where goods physically are (that is Ec::InventoryPhysicalReconciliationQuery).
    class BookLedger
      STALE_OPEN_ORDER_DAYS = 45
      OPEN_STATUSES = %w[pending processing].freeze
      WB_DISPATCHED_SUPPLIER_STATUS = "complete".freeze
      RECEIVED_BATCH_STATUSES = %w[received closed].freeze
      STATUS_BUCKETS = {
        "pending" => "pending", "processing" => "processing", "shipped" => "shipping", "delivered" => "signed"
      }.freeze

      def self.call(sku_codes:, as_of: nil)
        new(sku_codes: sku_codes, as_of: as_of).call
      end

      def self.compose(entry, platform_sellable:, platform_inbound:)
        platform_side = platform_sellable.to_i + platform_inbound.to_i
        own_side = entry[:ledger_total] - platform_side
        entry.merge(
          platform_sellable: platform_sellable.to_i,
          platform_inbound: platform_inbound.to_i,
          platform_side: platform_side,
          own_side: own_side,
          sellable: platform_sellable.to_i + own_side - entry[:return_in_transit_quantity].to_i -
            entry[:return_at_platform_quantity].to_i - entry[:unsellable_quantity].to_i
        )
      end

      def initialize(sku_codes:, as_of:)
        @sku_codes = Array(sku_codes).map { |code| code.to_s.upcase }.uniq
        @as_of = as_of
      end

      def call
        return {} if @sku_codes.empty?

        ledger = @sku_codes.index_with { empty_entry }
        apply_batches(ledger)
        apply_orders(ledger)
        ledger.each_value do |entry|
          entry[:ledger_total] = entry[:received_quantity] - entry[:gross_sales_quantity] + entry[:reversed_quantity]
        end
        ledger
      end

      private

      def empty_entry
        {
          purchase_quantity: 0, adjustment_quantity: 0, received_quantity: 0,
          gross_sales_quantity: 0, reversed_quantity: 0, ledger_total: 0,
          return_in_transit_quantity: 0, return_at_platform_quantity: 0, unsellable_quantity: 0,
          stale_open_order_quantity: 0, by_store: {}
        }
      end

      def apply_batches(ledger)
        scope = Ec::SkuBatch
          .where(sku_code: @sku_codes, status: RECEIVED_BATCH_STATUSES)
          .where.not(batch_type: :physical_stocktake_adjustment)
        if @as_of
          scope = scope.where(
            "ec_sku_batches.received_on <= :date OR (ec_sku_batches.received_on IS NULL AND ec_sku_batches.created_at <= :cutoff)",
            date: @as_of.to_date, cutoff: @as_of
          )
        end

        scope.group(:sku_code, :batch_type).sum(:received_quantity).each do |(sku_code, batch_type), quantity|
          entry = ledger[sku_code.to_s.upcase]
          next unless entry

          if batch_type.to_s == "normal"
            entry[:purchase_quantity] += quantity.to_i
          else
            entry[:adjustment_quantity] += quantity.to_i
          end
          entry[:received_quantity] += quantity.to_i
        end
      end

      ORDER_COLUMNS = %w[
        ec_sku_products.sku_code ec_order_items.order_id ec_order_items.platform ec_order_items.store_id
        ec_order_items.quantity ec_orders.order_status ec_orders.ordered_at ledger_f.status
        ledger_f.source_status ledger_f.source_substatus ledger_f.external_fulfillment_id
      ].freeze
      ORDER_KEYS = %i[
        sku_code order_id platform store_id quantity order_status ordered_at fulfillment_status
        fulfillment_source_status fulfillment_source_substatus external_fulfillment_id
      ].freeze

      def order_rows
        scope = Ec::OrderItem
          .joins(:order)
          .joins(Ec::InventoryOrderSalesDistributionQuery::ORDER_ITEM_JOIN)
          .joins("LEFT JOIN ec_order_fulfillments ledger_f ON ledger_f.id = ec_order_items.fulfillment_id")
          .where(ec_sku_products: { sku_code: @sku_codes })
        scope = scope.where("ec_orders.ordered_at <= ?", @as_of) if @as_of

        scope.pluck(*ORDER_COLUMNS.map { |column| Arel.sql(column) }).map do |values|
          row = ORDER_KEYS.zip(values).to_h
          row[:sku_code] = row[:sku_code].to_s.upcase
          row
        end
      end

      def apply_orders(ledger)
        stale_before = (@as_of || Time.current) - STALE_OPEN_ORDER_DAYS.days

        order_rows.group_by { |row| [ row[:order_id], row[:sku_code] ] }.each_value do |items|
          entry = ledger[items.first[:sku_code]]
          next unless entry

          items.each do |item|
            quantity = item[:quantity].to_i
            status = item[:fulfillment_status].presence || item[:order_status]

            if unsold_status?(item[:platform], status)
              next
            elsif OPEN_STATUSES.include?(status) && item[:ordered_at] && item[:ordered_at] < stale_before
              entry[:stale_open_order_quantity] += quantity
            else
              entry[:gross_sales_quantity] += quantity
              store_entry = store_entry(entry, item)
              store_entry[:gross_sales_quantity] += quantity
              bucket = STATUS_BUCKETS[status]
              store_entry[:status_counts][bucket] += quantity if bucket
            end
          end
        end
      end

      # Cancelled orders, and WB orders the platform marks as returned, are not sales.
      def unsold_status?(platform, status)
        status == "cancelled" || (platform == "wb" && status == "returned")
      end

      def store_entry(entry, item)
        entry[:by_store][[ item[:platform], item[:store_id] ]] ||= {
          gross_sales_quantity: 0, reversed_quantity: 0,
          status_counts: STATUS_BUCKETS.values.index_with { 0 }
        }
      end
    end
  end
end
