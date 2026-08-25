module RawOzon
  module Syncs
    module Chats
      CHAT_LIST_LIMIT = 100
      CHAT_HISTORY_LIMIT = 1000
      BUYER_CHAT_TYPE = "BUYER_SELLER"

      def sync_chats
        cursor = nil
        chat_count = 0
        message_count = 0
        synced_chat_ids = []

        loop do
          body = { limit: CHAT_LIST_LIMIT }
          body[:cursor] = cursor if cursor.present?
          response = @client.post("/v3/chat/list", body)
          items = Array(response["chats"])
          break if items.empty?

          rows = items.filter_map { |item| build_chat(item) }
          RawOzon::Chat.upsert_all(
            rows,
            unique_by: %i[account_id chat_id],
            update_only: %i[
              chat_type status unread_count first_unread_message_id last_message_id
              opened_at raw_json synced_at
            ]
          ) if rows.any?

          chat_ids = rows.map { |row| row[:chat_id] }
          synced_chat_ids.concat(chat_ids)
          chat_count += rows.size

          next_cursor = response["cursor"].presence
          break unless response["has_next"] && next_cursor && next_cursor != cursor

          cursor = next_cursor
        end

        RawOzon::Chat.where(
          account_id: @account.id,
          chat_id: synced_chat_ids.uniq,
          chat_type: BUYER_CHAT_TYPE
        ).find_each do |chat|
          next if chat_history_current?(chat)

          message_count += sync_chat_history(chat)
        end

        {
          ok: chat_count,
          chats: chat_count,
          messages: message_count,
          sku_links: RawOzon::ChatSkuLink.joins(:chat).where(raw_ozon_chats: { account_id: @account.id, chat_id: synced_chat_ids }).count,
        }
      end

      private

      def build_chat(item)
        chat = item["chat"] || item
        chat_id = chat["chat_id"].presence
        return unless chat_id

        {
          account_id: @account.id,
          chat_id: chat_id,
          chat_type: chat["chat_type"].presence || "UNSPECIFIED",
          status: chat["chat_status"],
          unread_count: item["unread_count"].to_i,
          first_unread_message_id: integer_or_nil(item["first_unread_message_id"]),
          last_message_id: integer_or_nil(item["last_message_id"]),
          opened_at: parse_time(chat["created_at"]),
          raw_json: item,
          synced_at: Time.current,
        }
      end

      def sync_chat_history(chat)
        messages = chat.messages
        backfilling = !chat.history_complete?
        marker = backfilling ? messages.minimum(:message_id) : messages.maximum(:message_id)
        fetched = 0

        loop do
          body = {
            chat_id: chat.chat_id,
            direction: backfilling ? "Backward" : "Forward",
            limit: CHAT_HISTORY_LIMIT,
          }
          body[:from_message_id] = marker if marker

          response = @client.post("/v3/chat/history", body)
          rows = Array(response["messages"]).filter_map { |message| build_message(chat, message) }
          upsert_chat_messages(rows)
          fetched += rows.size

          candidate = if backfilling
            rows.map { |row| row[:message_id] }.min
          else
            rows.map { |row| row[:message_id] }.max
          end
          break unless response["has_next"] && candidate && candidate != marker

          marker = candidate
        end

        refresh_chat_from_messages(chat, history_complete: backfilling || chat.history_complete?)
        refresh_chat_sku_links(chat)
        fetched
      end

      def chat_history_current?(chat)
        chat.history_complete? && chat.last_message_id.present? &&
          chat.messages.maximum(:message_id) == chat.last_message_id
      end

      def build_message(chat, message)
        message_id = integer_or_nil(message["message_id"] || message["id"])
        sent_at = parse_time(message["created_at"])
        return unless message_id && sent_at

        data = Array(message["data"])
        attachment_urls = data.flat_map { |part| part.to_s.scan(%r{https?://[^\s\)]+}) }.uniq
        text = data.reject { |part| part.blank? || part.to_s.match?(%r{\A!\[.*\]\(https?://}) }.join("\n").presence
        context = message["context"] || {}
        user = message["user"] || {}

        {
          chat_id: chat.id,
          message_id: message_id,
          user_id: user["id"]&.to_s,
          user_type: user["type"],
          message_text: text,
          message_data: data,
          is_read: ActiveModel::Type::Boolean.new.cast(message["is_read"]),
          is_image: ActiveModel::Type::Boolean.new.cast(message["is_image"]),
          attachment_urls: attachment_urls,
          platform_sku_id: context["sku"].presence&.to_s,
          order_number: context["order_number"].presence,
          sent_at: sent_at,
          raw_json: message,
          synced_at: Time.current,
        }
      end

      def upsert_chat_messages(rows)
        return if rows.empty?

        RawOzon::ChatMessage.upsert_all(
          rows,
          unique_by: %i[chat_id message_id],
          update_only: %i[
            user_id user_type message_text message_data is_read is_image attachment_urls
            platform_sku_id order_number sent_at raw_json synced_at
          ]
        )

        message_ids = rows.filter_map { |row| row[:message_id] if row[:attachment_urls].present? }
        RawOzon::ChatMessage.where(chat_id: rows.map { |row| row[:chat_id] }.uniq, message_id: message_ids)
          .find_each { |message| RawOzon::ChatImageStoreJob.perform_later(message.id) }
      end

      def refresh_chat_from_messages(chat, history_complete:)
        last_message = chat.messages.order(message_id: :desc).first
        chat.update!(
          last_message_at: last_message&.sent_at,
          last_message_user_type: last_message&.user_type,
          last_message_preview: last_message&.message_text&.truncate(500),
          history_synced_at: Time.current,
          history_complete: history_complete,
        )
      end

      def refresh_chat_sku_links(chat)
        store = Ec::Store.find_by(platform: "ozon", ozon_raw_account_id: @account.id)
        grouped = chat.messages.where.not(platform_sku_id: [nil, ""]).group(:platform_sku_id)
          .pluck(:platform_sku_id, Arel.sql("MIN(message_id)"), Arel.sql("MAX(message_id)"))
        return if grouped.empty?

        product_ids = if store
          Ec::SkuProduct.where(store_id: store.id, platform: "ozon", platform_sku_id: grouped.map(&:first))
            .pluck(:platform_sku_id, :id).to_h
        else
          {}
        end
        linked_at = Time.current
        rows = grouped.map do |platform_sku_id, first_message_id, last_message_id|
          {
            chat_id: chat.id,
            platform_sku_id: platform_sku_id,
            sku_product_id: product_ids[platform_sku_id],
            first_message_id: first_message_id,
            last_message_id: last_message_id,
            linked_at: linked_at,
          }
        end
        RawOzon::ChatSkuLink.upsert_all(
          rows,
          unique_by: %i[chat_id platform_sku_id],
          update_only: %i[sku_product_id first_message_id last_message_id linked_at]
        )
      end

      def integer_or_nil(value)
        Integer(value, exception: false)
      end

      def parse_time(value)
        Time.zone.parse(value.to_s) if value.present?
      rescue ArgumentError
        nil
      end
    end
  end
end
