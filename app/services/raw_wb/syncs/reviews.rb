module RawWb
  module Syncs
    module Reviews
      # GET /api/v1/feedbacks — feedbacks-api (offset pagination)
      def sync_reviews
        upsert_paginated(
          path:        '/api/v1/feedbacks',
          data_key:    'feedbacks',
          base_params: { isAnswered: 0, order: 'dateDesc' }
        ) { |r| build_review(r) }
      end

      private

      def build_review(r)
        return nil if r['id'].blank?
        details     = r['productDetails'] || {}
        answer      = r['answer'] || {}
        text        = safe_utf8(r['text'])
        answer_text = safe_utf8(answer['text'])
        photos = Array(r['photo'] || []).filter_map do |p|
          url = p['fullSize'] || p['miniSize']
          safe_utf8(url) if url
        end
        {
          account_id:    @account.id,
          wb_review_id:  r['id'].to_s,
          nm_id:         details['nmId'].to_i,
          vendor_code:   safe_utf8(details['supplierArticle']),
          size:          safe_utf8(details['size']),
          rating:        r['productValuation'].to_i,
          text:          text,
          photo_urls:    photos.to_json,
          video_urls:    [].to_json,
          was_viewed:    r['wasViewed'] || false,
          is_answered:   r['isAnswered'] || false,
          answer_text:   answer_text,
          answer_at:     answer['createDate'],
          is_pinned:     r['isPinned'] || false,
          is_archived:   false,
          wb_created_at: r['createdDate'],
          synced_at:     Time.current,
        }
      end
    end
  end
end
