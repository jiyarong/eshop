module RawOzon
  module Syncs
    module Reviews
      # POST /v1/review/list (last_id pagination, limit 20-100)
      def sync_reviews
        synced_at = Time.current
        fetch_last_id_paginated(
          path:      '/v1/review/list',
          body:      { sort_dir: 'DESC', status: 'ALL' },
          items_key: 'reviews',
          limit:     100,
        ) do |items|
          rows = items.map { |r| build_review(r, synced_at) }
          RawOzon::Review.upsert_all(rows, unique_by: [:account_id, :review_id],
                                     update_only: %i[response response_at response_status status synced_at]) if rows.any?
        end
      end

      private

      def build_review(r, synced_at)
        {
          account_id:      @account.id,
          review_id:       r['id'] || r['review_id'],
          ozon_sku:        r['sku'],
          offer_id:        r['offer_id'],
          product_name:    r['product_name'] || r.dig('items', 0, 'title'),
          reviewer_name:   r['reviewer_name'] || r.dig('author', 'name'),
          rating:          r['rating'],
          title:           r['title'],
          comment:         r['comment'] || r['text'],
          response:        r.dig('seller_comment', 'comment'),
          response_at:     r.dig('seller_comment', 'created_at'),
          response_status: r['seller_comment_status'],
          status:          r['status'],
          media:           r['media'],
          raw_json:        r,
          created_at:      r['created_at'],
          updated_at:      r['updated_at'],
          synced_at:       synced_at,
        }
      end
    end
  end
end
