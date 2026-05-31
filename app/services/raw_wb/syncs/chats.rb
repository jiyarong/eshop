module RawWb
  module Syncs
    module Chats
      # GET /api/v1/seller/chats — feedbacks-api
      def sync_chats
        data  = @client.get(:feedbacks, '/api/v1/seller/chats')
        items = Array(data.is_a?(Hash) ? data['chats'] || data : data)
        return 0 if items.empty?

        rows = items.filter_map { |r| build_chat(r) }
        RawWb::Chat.upsert_all(rows, unique_by: :wb_chat_id,
          update_only: %i[last_message_at updated_at]) if rows.any?
        rows.size
      end

      private

      def build_chat(r)
        chat_id = r['id'] || r['chatId']
        return nil if chat_id.blank?
        {
          account_id:      @account.id,
          wb_chat_id:      chat_id.to_s,
          buyer_id:        r['buyerId']&.to_s,
          last_message_at: r['lastMessageTime'] || r['updatedAt'],
          updated_at:      Time.current,
        }
      end
    end
  end
end
