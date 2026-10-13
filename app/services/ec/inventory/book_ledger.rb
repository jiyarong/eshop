module Ec
  module Inventory
    # Single source of truth for book stock: how many units the seller owns and how much of it is sellable.
    # Does not look at where goods physically are (that is Ec::InventoryPhysicalReconciliationQuery).
    class BookLedger
      STALE_OPEN_ORDER_DAYS = 45
      # First day snapshots use the ledger rules. Earlier persisted snapshots keep the old formula.
      EFFECTIVE_ON = Date.new(2026, 10, 14)
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

      UNATTRIBUTED_SQL = <<~SQL.squish.freeze
        NOT EXISTS (
          SELECT 1 FROM ec_sku_products p
          WHERE p.store_id = ec_order_items.store_id AND p.platform = ec_order_items.platform
            AND (
              (ec_order_items.platform = 'ozon' AND p.platform_sku_id = ec_order_items.platform_sku_id)
              OR (ec_order_items.platform = 'wb' AND p.product_id = ec_order_items.platform_sku_id)
            )
        )
      SQL

      def self.unattributed(as_of: nil)
        scope = Ec::OrderItem.joins(:order)
          .where.not(ec_orders: { order_status: "cancelled" })
          .where(UNATTRIBUTED_SQL)
        scope = scope.where("ec_orders.ordered_at <= ?", as_of) if as_of

        scope.group("ec_order_items.platform", "ec_order_items.platform_sku_id").sum(:quantity)
          .map { |(platform, platform_sku_id), quantity| { platform: platform, platform_sku_id: platform_sku_id, quantity: quantity.to_i } }
          .sort_by { |row| -row[:quantity] }
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
      ORDER_STATUS_SQL = "COALESCE(NULLIF(ledger_f.status, ''), ec_orders.order_status)".freeze
      UNSOLD_SQL = "(#{ORDER_STATUS_SQL} = 'cancelled' OR (ec_order_items.platform = 'wb' AND #{ORDER_STATUS_SQL} = 'returned'))".freeze
      HAS_RETURN_SQL = "EXISTS (SELECT 1 FROM ec_returns WHERE ec_returns.order_id = ec_order_items.order_id)".freeze

      def order_items_scope
        scope = Ec::OrderItem
          .joins(:order)
          .joins(Ec::InventoryOrderSalesDistributionQuery::ORDER_ITEM_JOIN)
          .joins("LEFT JOIN ec_order_fulfillments ledger_f ON ledger_f.id = ec_order_items.fulfillment_id")
          .where(ec_sku_products: { sku_code: @sku_codes })
        scope = scope.where("ec_orders.ordered_at <= ?", @as_of) if @as_of

        scope
      end

      # Most orders need only totals. Posting-level allocation is needed only
      # when goods were not sold or when a return belongs to the order.
      def detailed_order_scope
        order_items_scope.where("#{UNSOLD_SQL} OR #{HAS_RETURN_SQL}")
      end

      def apply_sales_totals(ledger, stale_before)
        stale_sql = Ec::OrderItem.sanitize_sql_array([
          "#{ORDER_STATUS_SQL} IN (?) AND ec_orders.ordered_at < ?", OPEN_STATUSES, stale_before
        ])
        order_items_scope.where("NOT #{UNSOLD_SQL}").where("NOT #{HAS_RETURN_SQL}")
          .group("ec_sku_products.sku_code", "ec_order_items.platform", "ec_order_items.store_id", Arel.sql(ORDER_STATUS_SQL))
          .pluck(
            Arel.sql("ec_sku_products.sku_code"), :platform, :store_id, Arel.sql(ORDER_STATUS_SQL),
            Arel.sql("SUM(CASE WHEN #{stale_sql} THEN 0 ELSE ec_order_items.quantity END)"),
            Arel.sql("SUM(CASE WHEN #{stale_sql} THEN ec_order_items.quantity ELSE 0 END)")
          ).each do |sku_code, platform, store_id, status, quantity, stale_quantity|
            entry = ledger[sku_code.to_s.upcase]
            entry[:stale_open_order_quantity] += stale_quantity.to_i
            next unless quantity.to_i.positive?

            entry[:gross_sales_quantity] += quantity.to_i
            store = store_entry(entry, platform: platform, store_id: store_id)
            store[:gross_sales_quantity] += quantity.to_i
            bucket = STATUS_BUCKETS[status]
            store[:status_counts][bucket] += quantity.to_i if bucket
          end
      end

      def order_rows
        detailed_order_scope.pluck(*ORDER_COLUMNS.map { |column| Arel.sql(column) }).map do |values|
          row = ORDER_KEYS.zip(values).to_h
          row[:sku_code] = row[:sku_code].to_s.upcase
          row
        end
      end

      def apply_orders(ledger)
        stale_before = (@as_of || Time.current) - STALE_OPEN_ORDER_DAYS.days
        apply_sales_totals(ledger, stale_before)
        rows = order_rows
        return if rows.empty?

        returns_by_order = Ec::Return.where(order_id: order_items_scope.select(:order_id))
          .includes(items: :sku_product).group_by(&:order_id)
        skus_by_order = order_sku_codes(returns_by_order)
        wb_dispatched = wb_dispatched_order_ids
        ozon_dispatched = ozon_dispatched_postings

        rows.group_by { |row| [ row[:order_id], row[:sku_code] ] }.each do |(order_id, sku_code), items|
          entry = ledger[sku_code]
          next unless entry

          returns = counting_returns(returns_by_order.fetch(order_id, []), sku_code, skus_by_order[order_id])
          sold = []
          unsold = []

          items.each do |item|
            quantity = item[:quantity].to_i
            status = row_status(item)

            if unsold_status?(item[:platform], status)
              unsold << { item: item, remaining: quantity, defect: item[:fulfillment_source_status] == "defect" }
            elsif OPEN_STATUSES.include?(status) && item[:ordered_at] && item[:ordered_at] < stale_before
              entry[:stale_open_order_quantity] += quantity
            else
              sold << { item: item, remaining: quantity }
              entry[:gross_sales_quantity] += quantity
              store_entry = store_entry(entry, item)
              store_entry[:gross_sales_quantity] += quantity
              bucket = STATUS_BUCKETS[status]
              store_entry[:status_counts][bucket] += quantity if bucket
            end
          end

          allocate_returns(entry, returns, sold, unsold)
          apply_undelivered_goods(entry, unsold, wb_dispatched, ozon_dispatched)
        end
      end

      def row_status(row)
        row[:fulfillment_status].presence || row[:order_status]
      end

      # Distinct SKU codes of every item on orders that have a return item without a matched SKU product, so
      # such an item can be attributed when the whole order belongs to one SKU.
      def order_sku_codes(returns_by_order)
        return {} unless returns_by_order.values.flatten.any? { |record| record.items.any? { |item| item.sku_product.nil? } }

        order_ids = Ec::ReturnItem.joins(:return).left_joins(:sku_product)
          .where(ec_sku_products: { id: nil })
          .where(ec_returns: { order_id: order_items_scope.select(:order_id) })
          .select("ec_returns.order_id")

        Ec::OrderItem.joins(Ec::InventoryOrderSalesDistributionQuery::ORDER_ITEM_JOIN)
          .where(order_id: order_ids).distinct
          .pluck(Arel.sql("ec_order_items.order_id"), Arel.sql("ec_sku_products.sku_code"))
          .group_by(&:first)
          .transform_values { |pairs| pairs.map { |_, code| code.to_s.upcase }.uniq }
      end

      # Distributes the returns of one order and SKU over its items. A return that names a posting is matched to
      # the items of that posting first (it never spills onto other postings); the rest is allocated order-wide.
      # Sold items consume a return first: goods are owned again whatever their location. Unsold items only
      # receive the location bucket of the goods that came back.
      def allocate_returns(entry, returns, sold, unsold)
        return if returns.empty?

        postings = (sold + unsold).filter_map { |slot| slot[:item][:external_fulfillment_id].presence }.to_set
        posting_returns, order_returns = returns.partition do |record|
          record[:posting].present? && postings.include?(record[:posting])
        end

        posting_returns.each do |record|
          matches = ->(slot) { slot[:item][:external_fulfillment_id] == record[:posting] }
          consume_return(entry, record, sold.select(&matches), unsold.select(&matches))
        end
        order_returns.each { |record| consume_return(entry, record, sold, unsold) }
      end

      def consume_return(entry, record, sold_slots, unsold_slots)
        sold_slots.each do |slot|
          take = [ record[:quantity], slot[:remaining] ].min
          next unless take.positive?

          slot[:remaining] -= take
          record[:quantity] -= take
          entry[:reversed_quantity] += take
          store_entry(entry, slot[:item])[:reversed_quantity] += take
          add_location_bucket(entry, record.merge(quantity: take))
        end

        unsold_slots.each do |slot|
          take = [ record[:quantity], slot[:remaining] ].min
          next unless take.positive?

          slot[:remaining] -= take
          record[:quantity] -= take
          # A WB order whose raw status is `defect` is unsellable whatever the return type says (spec 4.5).
          add_location_bucket(entry, record.merge(quantity: take, unsellable: record[:unsellable] || slot[:defect]))
        end
      end

      # Cancelled / WB-returned items nothing came back for: goods that already left are on their way back.
      def apply_undelivered_goods(entry, unsold, wb_dispatched, ozon_dispatched)
        unsold.each do |slot|
          next unless slot[:remaining].positive?
          next unless dispatched?(slot[:item], wb_dispatched, ozon_dispatched)

          if slot[:defect]
            entry[:unsellable_quantity] += slot[:remaining]
          else
            entry[:return_in_transit_quantity] += slot[:remaining]
          end
        end
      end

      def dispatched?(item, wb_dispatched, ozon_dispatched)
        case item[:platform]
        when "wb"
          item[:fulfillment_source_substatus] == WB_DISPATCHED_SUPPLIER_STATUS || wb_dispatched.include?(item[:order_id])
        when "ozon"
          ozon_dispatched.include?(item[:external_fulfillment_id])
        else
          false
        end
      end

      # Returns of this SKU on the order that count as goods coming back, as mutable hashes.
      # Returns hold current state only, so the as_of cut-off uses the best event time we have
      # (returned to seller, else requested, else created).
      def counting_returns(return_records, sku_code, order_sku_codes)
        single_sku_order = order_sku_codes == [ sku_code ]

        return_records.filter_map do |record|
          location = ReturnRules.location(record.platform, record.source_status)
          next unless location
          next if @as_of && (record.returned_to_seller_at || record.requested_at || record.created_at) > @as_of

          quantity = record.items
            .select do |item|
              item.sku_product ? item.sku_product.sku_code.to_s.upcase == sku_code : single_sku_order
            end
            .sum { |item| item.quantity.to_i }
          next unless quantity.positive?

          {
            location: location,
            quantity: quantity,
            posting: record.external_posting_number.presence,
            unsellable: ReturnRules.unsellable?(
              record.platform, reason: record.source_substatus, return_type: record.source_payload.to_h["return_type"]
            )
          }
        end
      end

      def add_location_bucket(entry, part)
        if part[:unsellable]
          entry[:unsellable_quantity] += part[:quantity]
        elsif part[:location] == :platform
          entry[:return_at_platform_quantity] += part[:quantity]
        elsif part[:location] == :transit
          entry[:return_in_transit_quantity] += part[:quantity]
        end
      end

      def wb_dispatched_order_ids
        Ec::OrderSourceLink
          .where(order_id: detailed_order_scope.where(platform: "wb").select(:order_id),
            source_type: "RawWb::Order", source_role: "primary")
          .joins("INNER JOIN raw_wb_orders ON raw_wb_orders.id = ec_order_source_links.source_id")
          .where(raw_wb_orders: { supplier_status: WB_DISPATCHED_SUPPLIER_STATUS })
          .pluck(:order_id).to_set
      end

      def ozon_dispatched_postings
        posting_numbers = detailed_order_scope.where(platform: "ozon").select("ledger_f.external_fulfillment_id")
        scope = RawOzon::PostingFbs.where(posting_number: posting_numbers).where.not(delivering_date: nil)
        scope = scope.where("delivering_date <= ?", @as_of) if @as_of
        scope.pluck(:posting_number).to_set
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
