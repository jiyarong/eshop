require "base64"
require "active_storage/service/qiniu_service"

module ActiveStorage
  class Service::QiniuService
    private

    def encode(value)
      Base64.strict_encode64(value.to_s).tr("+/", "-_")
    end
  end
end
