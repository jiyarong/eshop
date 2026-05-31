module RawWb
  module Syncs
    module SellerInfo
      # GET /api/v1/seller-info — common-api
      def sync_seller_info
        data = @client.get(:common, '/api/v1/seller-info')
        @account.update!(name: data['name']) if data.is_a?(Hash) && data['name']
        1
      end
    end
  end
end
