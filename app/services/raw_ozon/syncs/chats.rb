module RawOzon
  module Syncs
    module Chats
      # POST /v3/chat/list (offset pagination)
      def sync_chats
        offset    = 0
        total     = 0
        synced_at = Time.current
        limit     = 30

        loop do
          resp  = @client.post('/v3/chat/list', { limit: limit, offset: offset })
          chats = Array(resp['chats'])
          break if chats.empty?

          rows = chats.map { |c| build_chat(c, synced_at) }
          RawOzon::Chat.upsert_all(rows, unique_by: [:account_id, :chat_id],
                                   update_only: %i[unread_count status last_message synced_at]) if rows.any?
          total  += rows.size
          offset += limit
          break if chats.size < limit
          sleep 0.5
        end

        total
      end

      private

      def build_chat(c, synced_at)
        chat_data = c['chat'] || c
        {
          account_id:   @account.id,
          chat_id:      chat_data['chat_id'],
          chat_type:    chat_data['chat_type'],
          order_number: chat_data['order_number'],
          unread_count: c['unread_count'] || 0,
          status:       chat_data['status'],
          last_message: c['last_message'],
          raw_json:     c,
          synced_at:    synced_at,
        }
      end
    end
  end
end
