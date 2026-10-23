module Ec
  module OrderImport
    # Rewrites shipped_at of existing Ozon FBS fulfillments from the posting's delivering_date (the hand-over to
    # delivery). New and re-synced postings get the same value from Ec::OrderImport::Ozon; this repairs rows that
    # were imported earlier with the shipping deadline. Idempotent: only differing rows are touched.
    class OzonShippedAt
      def self.call(account_id: nil)
        new(account_id: account_id).call
      end

      def initialize(account_id: nil)
        @account_id = account_id
      end

      def call
        ActiveRecord::Base.connection.exec_update(<<~SQL.squish)
          UPDATE ec_order_fulfillments AS fulfillment
          SET shipped_at = postings.delivering_date,
              updated_at = NOW()
          FROM raw_ozon_postings_fbs AS postings
          WHERE fulfillment.platform = 'ozon'
            AND fulfillment.fulfillment_type = 'fbs'
            AND fulfillment.raw_source_type = 'RawOzon::PostingFbs'
            AND fulfillment.raw_source_id = postings.id#{account_condition}
            AND fulfillment.shipped_at IS DISTINCT FROM postings.delivering_date
        SQL
      end

      private

      def account_condition
        " AND postings.account_id = #{@account_id.to_i}" if @account_id
      end
    end
  end
end
