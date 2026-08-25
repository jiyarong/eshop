module RawOzon
  module ChatAttachment
    PATH_PREFIX = "/v2/chat/file/"
    CONTENT_TYPES = {
      ".gif" => "image/gif",
      ".heic" => "image/heic",
      ".heif" => "image/heif",
      ".jpeg" => "image/jpeg",
      ".jpg" => "image/jpeg",
      ".png" => "image/png",
      ".webp" => "image/webp",
      ".mov" => "video/quicktime",
      ".mp4" => "video/mp4",
    }.freeze

    module_function

    def parse(value)
      uri = URI.parse(value.to_s)
      extension = File.extname(uri.path).downcase
      return unless uri.scheme == "https" && uri.host == "api-seller.ozon.ru"
      return unless uri.path.start_with?(PATH_PREFIX) && CONTENT_TYPES.key?(extension)

      uri
    rescue URI::InvalidURIError
      nil
    end

    def content_type(uri)
      CONTENT_TYPES[File.extname(uri.path).downcase]
    end

    def video?(uri)
      content_type(uri).to_s.start_with?("video/")
    end
  end
end
