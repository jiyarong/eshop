module RawWb
  module Syncs
    module AdBalance
      # GET /adv/v1/balance — advert-api (ad account balance)
      def sync_ad_balance
        data    = @client.get(:advert, '/adv/v1/balance')
        balance = data.is_a?(Hash) ? (data['balance'] || data['net']).to_f : 0.0
        log "  Ad account balance: #{balance}"
        balance > 0 ? 1 : 0
      end
    end
  end
end
