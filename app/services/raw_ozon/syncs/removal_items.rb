require "digest"

module RawOzon
  module Syncs
    module RemovalItems
      SOURCES = {
        "stock" => "/v1/removal/from-stock/list",
        "supply" => "/v1/removal/from-supply/list"
      }.freeze

      def sync_removal_items
        synced_at = Time.current
        total = 0

        removal_date_chunks.each do |date_from, date_to|
          SOURCES.each do |source_type, path|
            total += sync_removal_source(
              source_type: source_type,
              path: path,
              date_from: date_from,
              date_to: date_to,
              synced_at: synced_at
            )
          end
        end

        total
      end

      private

      # A removal can stay active longer than DailySync's normal two-day window.
      # Re-read at least 90 days so later state transitions replace the stored row.
      def removal_date_chunks
        cursor = [@from.to_date, 89.days.ago.to_date].min
        chunks = []
        while cursor <= Date.current
          date_to = [cursor + 89, Date.current].min
          chunks << [cursor, date_to]
          cursor = date_to + 1
        end
        chunks
      end

      def sync_removal_source(source_type:, path:, date_from:, date_to:, synced_at:)
        all_items = []
        fetched = fetch_last_id_paginated(
          path: path,
          body: { "date_from" => date_from.iso8601, "date_to" => date_to.iso8601 },
          items_key: "returns_summary_report_rows",
          limit: 500
        ) { |items| all_items.concat(items) }

        rows = collapse_removal_items(all_items).map do |item, quantity, quant_count, source_row_count|
          build_removal_item(item, source_type, synced_at,
            quantity: quantity, quant_count: quant_count, source_row_count: source_row_count)
        end
        if rows.any?
          RawOzon::RemovalItem.upsert_all(
            rows,
            unique_by: %i[account_id source_type row_key],
            update_only: rows.first.keys - %i[account_id source_type row_key created_at updated_at]
          )
        end

        fetched
      end

      def collapse_removal_items(items)
        items.group_by { |item| removal_identity(item) }.values.map do |group|
          [
            group.first,
            group.sum { |item| item["quantity_for_return"].to_i },
            group.sum { |item| item["quant_count"].to_i },
            group.size
          ]
        end
      end

      def removal_identity(item)
        [item["return_id"], item["box_id"], item["sku"], item["offer_id"]].map(&:to_s).join("\0")
      end

      def build_removal_item(item, source_type, synced_at, quantity:, quant_count:, source_row_count:)
        identity = removal_identity(item)

        {
          account_id: @account.id,
          source_type: source_type,
          row_key: Digest::SHA256.hexdigest(identity),
          return_id: item["return_id"].to_s,
          box_id: item["box_id"].to_s,
          sku: item["sku"].to_s,
          offer_id: item["offer_id"],
          name: item["name"],
          quantity: quantity,
          quant_count: quant_count,
          stock_type: item["stock_type"],
          return_state: item["return_state"],
          box_state: item["box_state"],
          clearing_warehouse_name: item["clearing_warehouse_name"],
          destination_warehouse_name: item["destination_warehouse_name"],
          return_created_at: item["return_created_at"],
          delivery_date: item["delivery_date"],
          given_out_date: item["given_out_date"],
          utilization_date: item["utilization_date"],
          raw_json: item.merge("_source_row_count" => source_row_count),
          synced_at: synced_at,
          created_at: synced_at,
          updated_at: synced_at
        }
      end
    end
  end
end
