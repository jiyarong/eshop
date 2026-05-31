module RawOzon
  module Syncs
    module Questions
      # POST /v1/question/list (last_id pagination)
      def sync_questions
        synced_at = Time.current
        fetch_last_id_paginated(
          path:      '/v1/question/list',
          body:      { sort_dir: 'DESC', status: 'ALL' },
          items_key: 'questions',
          limit:     100,
        ) do |items|
          rows = items.map { |q| build_question(q, synced_at) }
          RawOzon::Question.upsert_all(rows, unique_by: [:account_id, :question_id],
                                       update_only: %i[answer answer_at status synced_at]) if rows.any?
        end
      end

      private

      def build_question(q, synced_at)
        answer = Array(q['answers']).first || {}
        {
          account_id:   @account.id,
          question_id:  q['id'] || q['question_id'],
          ozon_sku:     q['sku'],
          offer_id:     q['offer_id'],
          product_name: q['product_name'] || q.dig('product', 'name'),
          text:         q['text'] || q['question_text'],
          answer:       answer['text'],
          answer_at:    answer['created_at'],
          status:       q['status'],
          raw_json:     q,
          created_at:   q['created_at'],
          synced_at:    synced_at,
        }
      end
    end
  end
end
