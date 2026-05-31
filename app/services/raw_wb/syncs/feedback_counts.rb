module RawWb
  module Syncs
    module FeedbackCounts
      # GET /api/v1/feedbacks/count-unanswered — feedbacks-api
      def sync_feedback_counts
        data  = @client.get(:feedbacks, '/api/v1/feedbacks/count-unanswered')
        count = data.is_a?(Hash) ? (data['count'] || data['countUnanswered']).to_i : 0
        log "  Unanswered feedbacks: #{count}"
        count
      end
    end
  end
end
