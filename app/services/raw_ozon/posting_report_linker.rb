module RawOzon
  class PostingReportLinker
    def self.run(account: nil)
      scope = RawOzon::PostingReportItem.where(ec_order_item_id: nil)
      scope = scope.where(account_id: account.id) if account
      stats = { linked: 0, pending: 0, conflicts: 0 }

      stores = Ec::Store.where(platform: "ozon", ozon_raw_account_id: scope.select(:account_id)).index_by(&:ozon_raw_account_id)
      scope.find_each do |report_item|
        store = stores[report_item.account_id]
        matches = store && Ec::OrderItem.where(
          platform: "ozon",
          store_id: store.id,
          external_item_id: "#{report_item.posting_number}:#{report_item.ozon_sku}"
        ).limit(2).to_a

        if matches.blank?
          stats[:pending] += 1
        elsif matches.many?
          stats[:conflicts] += 1
        else
          RawOzon::PostingReportItem.transaction do
            report_item.update!(ec_order_item: matches.first)
            matches.first.update!(
              buyer_paid_unit_price: report_item.buyer_paid_unit_price,
              buyer_currency_code: report_item.buyer_currency_code,
              buyer_paid_synced_at: report_item.synced_at
            )
          end
          stats[:linked] += 1
        end
      end
      stats
    end
  end
end
