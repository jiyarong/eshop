module RawWb
  module Syncs
    module Balance
      # GET /api/v1/account/balance — finance-api (inserts a new snapshot each run)
      def sync_balance
        data = @client.get(:finance, '/api/v1/account/balance')
        return 0 unless data.is_a?(Hash) && data['currency']

        RawWb::AccountBalance.create!(
          account_id:   @account.id,
          currency:     data['currency'],
          current:      data['current'].to_f,
          for_withdraw: data['for_withdraw'].to_f,
          snapshot_at:  Time.current,
        )
        1
      end
    end
  end
end
