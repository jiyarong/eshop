module RawWb
  module Syncs
    module UnreadFeedbacks
      # GET /api/v1/new-feedbacks-questions — feedbacks-api (returns true/false)
      def sync_unread_feedbacks
        data       = @client.get(:feedbacks, '/api/v1/new-feedbacks-questions')
        has_unread = data == true || (data.is_a?(Hash) && data['hasUnread'] == true)
        log "  Unread feedbacks/questions: #{has_unread}"
        has_unread ? 1 : 0
      end
    end
  end
end
