module RawWb
  module Syncs
    module Questions
      # GET /api/v1/questions — feedbacks-api (offset pagination)
      def sync_questions
        upsert_paginated(
          path:        '/api/v1/questions',
          data_key:    'questions',
          base_params: { isAnswered: 0, order: 'dateDesc' }
        ) { |r| build_question(r) }
      end

      private

      def build_question(r)
        return nil if r['id'].blank?
        details = r['productDetails'] || {}
        answer  = r['answer'] || {}
        {
          account_id:     @account.id,
          wb_question_id: r['id'].to_s,
          nm_id:          details['nmId'].to_i,
          vendor_code:    safe_utf8(details['supplierArticle']),
          text:           safe_utf8(r['text']),
          was_viewed:     r['wasViewed'] || false,
          is_answered:    r['isAnswered'] || false,
          answer_text:    safe_utf8(answer['text']),
          answer_at:      answer['createDate'],
          wb_created_at:  r['createdDate'],
          synced_at:      Time.current,
        }
      end
    end
  end
end
