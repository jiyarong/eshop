require "base64"
require "active_storage/service/qiniu_service"

unless URI.respond_to?(:escape)
  def URI.escape(value)
    URI::DEFAULT_PARSER.escape(value.to_s)
  end
end

module ActiveStorage
  class Service::QiniuService
    private

    def url_expires_in
      ActiveStorage.service_urls_expire_in
    end

    def encode(value)
      Base64.strict_encode64(value.to_s).tr("+/", "-_")
    end
  end
end
