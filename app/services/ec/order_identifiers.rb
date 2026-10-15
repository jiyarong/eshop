module Ec
  # Every identifier an order produced along its chain (order, posting, label, supply, return, ...), so an
  # operator can pick the one the platform cabinet understands. The meaning of each value is deliberately loose:
  # the entries only carry a label key (translated under orders.identifiers) and the value.
  #
  # Loads everything for a page of orders with a fixed number of queries.
  class OrderIdentifiers
    Entry = Data.define(:key, :value)

    def self.for_orders(orders)
      new(orders).call
    end

    def initialize(orders)
      @orders = orders.to_a
    end

    # { order_id => [Entry, ...] }, without repeated values.
    def call
      return {} if @orders.empty?

      load_sources
      @orders.to_h { |order| [ order.id, unique(entries_for(order)) ] }
    end

    private

    def load_sources
      order_ids = @orders.map(&:id)
      @links = Ec::OrderSourceLink.where(order_id: order_ids, source_role: "primary").to_a.group_by(&:order_id)
      @fbs_postings = RawOzon::PostingFbs.where(id: source_ids("RawOzon::PostingFbs")).index_by(&:id)
      @fbo_postings = RawOzon::PostingFbo.where(id: source_ids("RawOzon::PostingFbo")).index_by(&:id)
      @wb_orders = RawWb::Order.where(id: source_ids("RawWb::Order")).index_by(&:id)
      @wb_stats_orders = RawWb::StatsOrder.where(id: source_ids("RawWb::StatsOrder")).index_by(&:id)
      load_wb_related
      load_returns(order_ids)
    end

    def source_ids(type)
      @links.values.flatten.select { |link| link.source_type == type }.map(&:source_id)
    end

    def load_wb_related
      srids = (@wb_orders.values.map(&:srid) + @wb_stats_orders.values.map(&:srid)).compact_blank.uniq
      @wb_sale_ids_by_srid = RawWb::StatsSale.where(srid: srids).pluck(:srid, :sale_id).group_by(&:first)
        .transform_values { |rows| rows.map(&:last).compact_blank.uniq }
      @wb_supply_ids_by_order = RawWb::SupplyOrder.where(order_id: @wb_orders.keys)
        .joins("INNER JOIN raw_wb_supplies ON raw_wb_supplies.id = raw_wb_supply_orders.supply_id")
        .pluck(:order_id, "raw_wb_supplies.wb_supply_id").group_by(&:first)
        .transform_values { |rows| rows.map(&:last).compact_blank.uniq }
    end

    def load_returns(order_ids)
      @returns_by_order = Ec::Return.where(order_id: order_ids).to_a.group_by(&:order_id)
      return_ids = @returns_by_order.values.flatten.map(&:id)
      links = Ec::ReturnSourceLink.where(return_id: return_ids).to_a
      @ozon_returns = RawOzon::Return.where(
        id: links.select { |link| link.source_type == "RawOzon::Return" }.map(&:source_id)
      ).to_a.group_by { |raw| raw.return_id.to_s }
      @wb_returns = RawWb::GoodsReturn.where(
        id: links.select { |link| link.source_type == "RawWb::GoodsReturn" }.map(&:source_id)
      ).to_a.group_by { |raw| raw.shk_id.to_s }
    end

    def entries_for(order)
      entries = []
      Array(@links[order.id]).each do |link|
        case link.source_type
        when "RawOzon::PostingFbs" then entries.concat(ozon_fbs_entries(@fbs_postings[link.source_id]))
        when "RawOzon::PostingFbo" then entries.concat(ozon_fbo_entries(@fbo_postings[link.source_id]))
        when "RawWb::Order" then entries.concat(wb_order_entries(@wb_orders[link.source_id]))
        when "RawWb::StatsOrder" then entries.concat(wb_stats_entries(@wb_stats_orders[link.source_id]))
        end
      end
      entries.concat(order_entries(order))
      Array(@returns_by_order[order.id]).each { |ret| entries.concat(return_entries(ret)) }
      entries
    end

    def order_entries(order)
      entries = [
        entry(:platform_order_id, order.external_order_id),
        entry(:platform_order_number, order.external_order_number)
      ]
      order.fulfillments.each do |fulfillment|
        entries << entry(:fulfillment_id, fulfillment.external_fulfillment_id)
        entries << entry(:tracking_number, fulfillment.tracking_number)
      end
      order.items.each { |item| entries << entry(:item_id, item.external_item_id) }
      entries
    end

    def ozon_fbs_entries(posting)
      return [] unless posting

      barcodes = posting.raw_json.to_h["barcodes"].to_h
      [
        entry(:posting_number, posting.posting_number),
        entry(:ozon_order_id, posting.order_id),
        entry(:ozon_order_number, posting.order_number),
        entry(:parent_posting_number, posting.parent_posting_number),
        entry(:tracking_number, posting.tracking_number),
        entry(:label_barcode, barcodes["upper_barcode"]),
        entry(:label_barcode, barcodes["lower_barcode"])
      ]
    end

    def ozon_fbo_entries(posting)
      return [] unless posting

      [
        entry(:posting_number, posting.posting_number),
        entry(:ozon_order_id, posting.order_id),
        entry(:ozon_order_number, posting.order_number)
      ]
    end

    def wb_order_entries(raw)
      return [] unless raw

      [
        entry(:wb_task_id, raw.wb_order_id),
        entry(:order_uid, raw.order_uid),
        entry(:srid, raw.srid),
        entry(:g_number, raw.g_number)
      ] +
        Array(@wb_sale_ids_by_srid[raw.srid]).map { |sale_id| entry(:sale_id, sale_id) } +
        Array(@wb_supply_ids_by_order[raw.id]).map { |supply_id| entry(:supply_id, supply_id) }
    end

    def wb_stats_entries(raw)
      return [] unless raw

      [
        entry(:srid, raw.srid),
        entry(:g_number, raw.g_number),
        entry(:sticker, raw.sticker)
      ] + Array(@wb_sale_ids_by_srid[raw.srid]).map { |sale_id| entry(:sale_id, sale_id) }
    end

    def return_entries(record)
      entries = [
        entry(:return_id, record.external_return_id),
        entry(:return_posting_number, record.external_posting_number)
      ]
      Array(@ozon_returns[record.external_return_id.to_s]).each do |raw|
        payload = raw.raw_json.to_h
        entries << entry(:clearing_id, payload["clearing_id"])
        entries << entry(:clearing_id, payload["return_clearing_id"])
        entries << entry(:return_barcode, payload.dig("logistic", "barcode"))
      end
      Array(@wb_returns[record.external_return_id.to_s]).each do |raw|
        entries << entry(:sticker, raw.sticker_id)
        entries << entry(:return_barcode, raw.barcode)
      end
      entries
    end

    def entry(key, value)
      value = value.to_s.strip
      value.empty? || value == "0" ? nil : Entry.new(key: key, value: value)
    end

    def unique(entries)
      entries.compact.uniq(&:value)
    end
  end
end
