module RawWb
  module Syncs
    module Ping
      # GET /ping — common-api
      def sync_ping
        @client.get(:common, '/ping')
        1
      end
    end
  end
end
