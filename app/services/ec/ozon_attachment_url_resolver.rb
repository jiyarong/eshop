require "uri"

module Ec
  class OzonAttachmentUrlResolver
    def initialize(url_generator: nil)
      @url_generator = url_generator
    end

    def call(attachment)
      return normalize(attachment) if attachment.is_a?(String)

      url = if attachment.respond_to?(:oss_path) && attachment.oss_path.to_s.start_with?("https://")
        attachment.oss_path
      elsif attachment.respond_to?(:file) && attachment.file.attached?
        if @url_generator
          @url_generator.call(attachment)
        else
          attachment.file.url(disposition: :inline, filename: attachment.filename)
        end
      end
      normalize(url)
    end

    def resolve_all(attachments)
      Array(attachments).filter_map { |attachment| call(attachment) }.uniq
    end

    private

    def normalize(value)
      uri = URI.parse(value.to_s)
      return unless uri.is_a?(URI::HTTPS) && uri.host.present?
      return if uri.path.to_s.start_with?("/rails/active_storage")

      uri.to_s
    rescue URI::InvalidURIError
      nil
    end
  end
end
