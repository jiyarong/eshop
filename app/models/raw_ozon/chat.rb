module RawOzon
  class Chat < ApplicationRecord
    self.table_name = 'raw_ozon_chats'
    belongs_to :account, class_name: 'RawOzon::SellerAccount'
    has_many :messages, class_name: 'RawOzon::ChatMessage', dependent: :delete_all
    has_many :sku_links, class_name: 'RawOzon::ChatSkuLink', dependent: :delete_all
    has_many :sku_products, through: :sku_links
  end
end
