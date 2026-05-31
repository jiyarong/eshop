module RawWb
  module Syncs
    module QuestionCounts
      # GET /api/v1/questions/count-unanswered — feedbacks-api
      def sync_question_counts
        data  = @client.get(:feedbacks, '/api/v1/questions/count-unanswered')
        count = data.is_a?(Hash) ? (data['count'] || data['countUnanswered']).to_i : 0
        log "  Unanswered questions: #{count}"
        count
      end
    end
  end
end
