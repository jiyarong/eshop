module RawOzon
  class PostingReportImport
    def initialize(report:, body:, buyer_paid_value_kind:)
      @report = report
      @rows = PostingReportCsvParser.new(body, buyer_paid_value_kind:).parse
      @schema = report.params.fetch("delivery_schema").to_s
      @synced_at = Time.current
    end

    def call
      stats = { rows: @rows.size, imported: 0, linked: 0, pending: 0, conflicts: 0, stale: 0 }
      store = Ec::Store.find_by(platform: "ozon", ozon_raw_account_id: @report.account_id)

      RawOzon::PostingReportItem.transaction do
        @rows.each do |attributes|
          item = RawOzon::PostingReportItem.lock.find_or_initialize_by(
            account_id: @report.account_id,
            delivery_schema: @schema,
            posting_number: attributes.fetch(:posting_number),
            ozon_sku: attributes.fetch(:ozon_sku)
          )
          if newer_report?(item)
            stats[:stale] += 1
            next
          end

          item.assign_attributes(attributes.merge(report: @report, synced_at: @synced_at))
          outcome = link(item, store)
          stats[outcome] += 1
          item.save!
          update_order_item(item) if outcome == :linked
          stats[:imported] += 1
        end
      end
      stats
    end

    private

    def newer_report?(item)
      item.persisted? && item.report && item.report.created_at && @report.created_at && item.report.created_at > @report.created_at
    end

    def link(item, store)
      return :pending unless store

      matches = Ec::OrderItem.where(
        platform: "ozon",
        store_id: store.id,
        external_item_id: "#{item.posting_number}:#{item.ozon_sku}"
      ).limit(2).to_a
      return :pending if matches.empty?
      return :conflicts if matches.many?

      existing_link = RawOzon::PostingReportItem.where(ec_order_item_id: matches.first.id).where.not(id: item.id).exists?
      if existing_link
        item.ec_order_item = nil
        return :conflicts
      end

      item.ec_order_item = matches.first
      :linked
    end

    def update_order_item(item)
      item.ec_order_item.update!(
        buyer_paid_unit_price: item.buyer_paid_unit_price,
        buyer_currency_code: item.buyer_currency_code,
        buyer_paid_synced_at: item.synced_at
      )
    end
  end
end
