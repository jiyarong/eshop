module RawOzon
  class ChatSkuLink < ApplicationRecord
    self.table_name = "raw_ozon_chat_sku_links"

    belongs_to :chat, class_name: "RawOzon::Chat"
    belongs_to :sku_product, class_name: "Ec::SkuProduct", optional: true
  end
end
