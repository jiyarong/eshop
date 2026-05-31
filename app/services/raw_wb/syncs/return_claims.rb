module RawWb
  module Syncs
    module ReturnClaims
      # GET /api/v1/claims — feedbacks-api (buyer return requests)
      def sync_return_claims
        data  = @client.get(:feedbacks, '/api/v1/claims')
        items = Array(data.is_a?(Hash) ? data['claims'] || data['data'] : data)
        return 0 if items.empty?

        rows = items.filter_map { |r| build_return_claim(r) }
        RawWb::ReturnClaim.upsert_all(rows, unique_by: :wb_claim_id,
          update_only: %i[status response_text responded_at synced_at]) if rows.any?
        rows.size
      end

      private

      def build_return_claim(r)
        claim_id = r['claimID'] || r['id']
        return nil if claim_id.blank?
        {
          account_id:    @account.id,
          wb_claim_id:   claim_id.to_s,
          nm_id:         r['nmID'] || r['nmId'],
          status:        r['status'],
          reason:        r['reason'],
          response_text: r['responseText'],
          wb_created_at: r['createdDate'] || r['createdAt'],
          responded_at:  r['respondedAt'],
          synced_at:     Time.current,
        }
      end
    end
  end
end
