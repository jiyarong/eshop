module RawOzon
  class ChatImageBackfillJob < ApplicationJob
    queue_as :default

    def perform(account_id: nil, limit: nil, inline: false)
      scope = RawOzon::ChatMessage.joins(:chat).where.not(attachment_urls: []).order(:id)
      scope = scope.where(raw_ozon_chats: { account_id: account_id }) if account_id.present?
      enqueued = 0

      scope.includes(images_attachments: :blob).find_each do |message|
        next unless missing_image?(message)

        inline ? RawOzon::ChatImageStoreJob.perform_now(message.id) : RawOzon::ChatImageStoreJob.perform_later(message.id)
        enqueued += 1
        break if limit.present? && enqueued >= limit.to_i
      end

      enqueued
    end

    private

    def missing_image?(message)
      stored_urls = message.images_attachments.map { |attachment| attachment.blob.metadata["source_url"] }
      Array(message.attachment_urls).any? { |url| !stored_urls.include?(url) }
    end
  end
end
