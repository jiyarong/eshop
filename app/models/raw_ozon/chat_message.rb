module RawOzon
  class ChatMessage < ApplicationRecord
    self.table_name = 'raw_ozon_chat_messages'
    belongs_to :chat, class_name: 'RawOzon::Chat'
    has_many_attached :images

    def stored_image_for(source_url)
      attachments = images_attachments.loaded? ? images_attachments : images_attachments.includes(:blob)
      attachments.find do |attachment|
        attachment.blob.metadata["source_url"] == source_url
      end
    end
  end
end
