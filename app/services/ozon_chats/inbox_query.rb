module OzonChats
  class InboxQuery
    BUYER_CHAT_TYPE = "BUYER_SELLER"

    def initialize(store:, sku_codes: nil)
      @store = store
      @sku_codes = Array(sku_codes).reject(&:blank?).uniq
    end

    def scope
      chats = RawOzon::Chat.where(
        account_id: @store.ozon_raw_account_id,
        chat_type: BUYER_CHAT_TYPE
      )
      chats = filter_by_skus(chats) if @sku_codes.any?
      chats.order(Arel.sql("last_message_at DESC NULLS LAST"), id: :desc)
    end

    private

    def filter_by_skus(chats)
      sku_product_ids = Ec::SkuProduct.where(
        store_id: @store.id,
        platform: "ozon",
        sku_code: @sku_codes
      ).select(:id)

      chats.joins(:sku_links)
        .where(raw_ozon_chat_sku_links: { sku_product_id: sku_product_ids })
        .distinct
    end
  end
end
