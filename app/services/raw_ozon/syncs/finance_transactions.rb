module RawOzon
  module Syncs
    module FinanceTransactions
      # POST /v3/finance/transaction/list (page pagination)
      def sync_finance_transactions
        synced_at = Time.current
        total     = 0
        month_chunks.each do |chunk_from, chunk_to|
          fetch_offset_paginated(
            path:      '/v3/finance/transaction/list',
            body:      {
              filter: {
                date:             { from: "#{chunk_from}T00:00:00Z", to: "#{chunk_to}T23:59:59Z" },
                operation_type:   [],
                transaction_type: 'all',
              },
            },
            items_key:  'operations',
            page_size:  1000,
          ) do |items|
            rows = items.map { |op| build_transaction(op, synced_at) }
            RawOzon::FinanceTransaction.upsert_all(rows, unique_by: [:account_id, :operation_id]) if rows.any?
            total += rows.size
          end
          sleep 1
        end
        total
      end

      private

      def build_transaction(op, synced_at)
        {
          account_id:             @account.id,
          operation_id:           op['operation_id'],
          operation_type:         op['operation_type'],
          operation_type_name:    op['operation_type_name'],
          posting_number:         op['posting']['posting_number'],
          order_number:           op['posting']['order_number'],
          amount:                 op['amount'].to_f,
          currency_code:          'RUB',
          accruals_for_sale:      op['accruals_for_sale'].to_f,
          sale_commission:        op['sale_commission'].to_f,
          delivery_charge:        op['delivery_charge'].to_f,
          return_delivery_charge: op['return_delivery_charge'].to_f,
          items:                  op['items'],
          services:               op['services'],
          raw_json:               op,
          operation_date:         op['operation_date'],
          order_date:             op['posting']['order_date'],
          synced_at:              synced_at,
        }
      end
    end
  end
end
