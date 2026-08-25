module Reports
  class OzonChatsController < ApplicationController
    include SpuSkuFilterable

    CHAT_PAGE_SIZE = 30
    MESSAGE_PAGE_SIZE = 100
    before_action -> { require_permission!(:view_reports) }

    def index
      load_context
      load_chats
      load_selected_chat
      load_messages

      respond_to do |format|
        format.html
        format.json { render json: json_payload }
      end
    end

    def attachment
      store = Ec::Store.active.where(platform: "ozon").find(positive_integer(params[:store_id]))
      chat = RawOzon::Chat.find_by!(account_id: store.ozon_raw_account_id, chat_id: params[:chat_id])
      message = chat.messages.find_by!(message_id: params[:message_id])
      uri = attachment_uri(message)

      if (stored_image = message.stored_image_for(uri.to_s))
        return redirect_to rails_blob_path(stored_image, disposition: "inline")
      end

      head :not_found
    end

    private

    def load_context
      @stores = Ec::Store.active.where(platform: "ozon").where.not(ozon_raw_account_id: nil).order(:id)
      @store = @stores.find_by(id: positive_integer(params[:store_id])) || @stores.first
      raise ActiveRecord::RecordNotFound, t("reports.ozon_chats.errors.no_store") unless @store

      load_spu_sku_filter
      @selected_sku_codes = if spu_sku_filter_active?
        apply_spu_sku_filter_to_skus(Ec::Sku.all).pluck(:sku_code)
      end
    end

    def load_chats
      @chat_scope = OzonChats::InboxQuery.new(store: @store, sku_codes: @selected_sku_codes).scope
        .includes(sku_links: :sku_product)
      @chats = @chat_scope.page(positive_integer(params[:page]) || 1).per(CHAT_PAGE_SIZE)
      if @chats.total_pages.positive? && @chats.current_page > @chats.total_pages
        @chats = @chat_scope.page(@chats.total_pages).per(CHAT_PAGE_SIZE)
      end
    end

    def load_selected_chat
      @explicit_chat = params[:chat_id].present?
      @selected_chat = if @explicit_chat
        @chat_scope.find_by(chat_id: params[:chat_id].to_s)
      else
        @chats.first
      end
    end

    def load_messages
      return unless @selected_chat

      scope = @selected_chat.messages.with_attached_images.order(message_id: :desc)
      @message_page = scope.page(positive_integer(params[:message_page]) || 1).per(MESSAGE_PAGE_SIZE)
      if @message_page.total_pages.positive? && @message_page.current_page > @message_page.total_pages
        @message_page = scope.page(@message_page.total_pages).per(MESSAGE_PAGE_SIZE)
      end
      @messages = @message_page.to_a.reverse
    end

    def positive_integer(value)
      parsed = Integer(value, exception: false)
      parsed if parsed&.positive?
    end

    def attachment_uri(message)
      index = Integer(params[:attachment_index], exception: false)
      raise ActiveRecord::RecordNotFound unless index && index >= 0

      uri = RawOzon::ChatAttachment.parse(Array(message.attachment_urls)[index])
      uri || raise(ActiveRecord::RecordNotFound)
    end

    def json_payload
      {
        store: { id: @store.id, name: @store.store_name },
        filters: { sku_codes: @selected_sku_codes || [] },
        chats: @chats.map { |chat| chat_json(chat) },
        pagination: pagination_json(@chats),
        selected_chat: @selected_chat && chat_json(@selected_chat),
        messages: Array(@messages).map { |message| message_json(message) },
        message_pagination: @message_page && pagination_json(@message_page),
      }
    end

    def chat_json(chat)
      {
        chat_id: chat.chat_id,
        unread_count: chat.unread_count,
        last_message_at: chat.last_message_at,
        last_message_user_type: chat.last_message_user_type,
        last_message_preview: chat.last_message_preview,
        sku_codes: chat.sku_products.map(&:sku_code).uniq,
      }
    end

    def message_json(message)
      {
        message_id: message.message_id,
        user_type: message.user_type,
        text: message.message_text,
        sent_at: message.sent_at,
        is_read: message.is_read,
        is_image: message.is_image,
        attachment_urls: message.attachment_urls,
        platform_sku_id: message.platform_sku_id,
      }
    end

    def pagination_json(records)
      {
        page: records.current_page,
        per_page: records.limit_value,
        total_pages: records.total_pages,
        total_count: records.total_count,
      }
    end
  end
end
