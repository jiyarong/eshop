require "test_helper"

class QiniuServiceEncodingTest < ActiveSupport::TestCase
  test "qiniu service encodes long upload keys without newlines" do
    key = "ec/skus/2/attachments/1b9f42dd-91eb-490f-85a9-c0f865ffd5cf/robots.txt"
    encoded = ActiveStorage::Service::QiniuService.allocate.send(:encode, key)

    assert_no_match(/\s/, encoded)
    assert_equal Base64.strict_encode64(key).tr("+/", "-_"), encoded
  end
end
