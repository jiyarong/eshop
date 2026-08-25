require "stringio"

module RawOzon
  class ChatImageStoreJob < ApplicationJob
    queue_as :default

    def perform(message_id)
      message = RawOzon::ChatMessage.includes(chat: :account).find(message_id)
      client = RawOzon::OzonClient.new(message.chat.account.client_id, message.chat.account.api_key)

      Array(message.attachment_urls).each do |source_url|
        uri = RawOzon::ChatAttachment.parse(source_url)
        next unless uri
        next if message.stored_image_for(source_url)

        store_image(message, client, uri, source_url)
      end
    end

    private

    def store_image(message, client, uri, source_url)
      extension = File.extname(uri.path).downcase
      key = storage_key("ozon/chats/#{Digest::SHA256.hexdigest(source_url)}#{extension}")
      blob = ActiveStorage::Blob.find_by(key: key)
      blob ||= ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new(client.download(uri.request_uri).fetch(:body)),
        filename: File.basename(uri.path),
        content_type: RawOzon::ChatAttachment.content_type(uri),
        key: key,
        metadata: { "source_url" => source_url }
      )
      message.images.attach(blob) unless message.images.blobs.exists?(blob.id)
    rescue ActiveRecord::RecordNotUnique
      retry
    end

    def storage_key(key)
      if Rails.env.development? && ActiveStorage::Blob.service.name.to_s == "qiniu"
        "development/#{key}"
      else
        key
      end
    end
  end
end
