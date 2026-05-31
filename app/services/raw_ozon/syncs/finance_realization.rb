module RawOzon
  module Syncs
    module FinanceRealization
      # POST /v2/finance/realization — 同步上个月的对账报表
      def sync_finance_realization
        target = 1.month.ago
        resp   = @client.post('/v2/finance/realization', {
          month: target.month,
          year:  target.year,
        })

        report_date = Date.new(target.year, target.month, 1)
        row = {
          account_id:          @account.id,
          report_date:         report_date,
          doc_number:          resp['doc_number'],
          doc_date:            resp['doc_date'],
          accruals_for_sale:   resp['accruals_for_sale'].to_f,
          compensation_amount: resp['compensation_amount'].to_f,
          money_transfer:      resp['money_transfer'].to_f,
          total_amount:        resp['total_amount'].to_f,
          start_balance:       resp['start_balance'].to_f,
          close_balance:       resp['close_balance'].to_f,
          rows:                resp['rows'],
          raw_json:            resp,
          synced_at:           Time.current,
        }
        RawOzon::FinanceRealization.upsert(row, unique_by: [:account_id, :report_date])
        1
      end
    end
  end
end
