require "base64"
require "active_storage/service/qiniu_service"

unless URI.respond_to?(:escape)
  def URI.escape(value)
    URI::DEFAULT_PARSER.escape(value.to_s)
  end
end

module ActiveStorage
  class Service::QiniuService
    DOWNLOAD_TIMEOUT_OPTIONS = { open_timeout: 5, read_timeout: 15 }.freeze

    def download(key)
      if block_given?
        instrument :streaming_download, key: key do
          URI.open(url(key, disposition: :attachment), **DOWNLOAD_TIMEOUT_OPTIONS) do |file|
            yield file.read(64.kilobytes) while !file.eof?
          end
        end
      else
        instrument :download, key: key do
          URI.open(url(key, disposition: :attachment), **DOWNLOAD_TIMEOUT_OPTIONS, &:read)
        end
      end
    end

    private

    def url_expires_in
      ActiveStorage.service_urls_expire_in.to_i
    end

    def encode(value)
      Base64.strict_encode64(value.to_s).tr("+/", "-_")
    end
  end
end
