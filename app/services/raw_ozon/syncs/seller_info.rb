module RawOzon
  module Syncs
    module SellerInfo
      # POST /v1/seller/info
      def sync_seller_info
        resp = @client.post('/v1/seller/info', {})
        @account.update!(
          company_name:   resp.dig('company', 'name'),
          legal_name:     resp.dig('company', 'legal_name'),
          inn:            resp.dig('company', 'inn'),
          ownership_form: resp.dig('company', 'ownership_form'),
          raw_json:       resp,
        )
        1
      end
    end
  end
end
