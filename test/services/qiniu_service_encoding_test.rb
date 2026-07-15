require "test_helper"

class QiniuServiceEncodingTest < ActiveSupport::TestCase
  test "qiniu service escapes attachment filenames on current Ruby versions" do
    service = ActiveStorage::Service::QiniuService.new(
      access_key: "test-access-key",
      secret_key: "test-secret-key",
      bucket: "test-bucket",
      domain: "assets.example.test"
    )

    url = service.url(
      "skills/initial.zip",
      disposition: :attachment,
      filename: ActiveStorage::Filename.new("初始 skill.zip")
    )

    assert_equal(
      "https://assets.example.test/skills%2Finitial.zip?attname=%E5%88%9D%E5%A7%8B%20skill.zip",
      url
    )
  end

  test "qiniu private service uses the Active Storage URL expiration" do
    service = ActiveStorage::Service::QiniuService.new(
      access_key: "test-access-key",
      secret_key: "test-secret-key",
      bucket: "test-bucket",
      domain: "assets.example.test",
      bucket_private: true
    )
    captured_options = nil
    original_method = Qiniu::Auth.method(:authorize_download_url_2)
    Qiniu::Auth.define_singleton_method(:authorize_download_url_2) do |_domain, _key, options|
      captured_options = options
      "signed-url"
    end

    begin
      url = service.url("skills/initial.zip", disposition: :attachment)
    ensure
      Qiniu::Auth.define_singleton_method(:authorize_download_url_2, original_method)
    end

    assert_equal "signed-url", url
    assert_equal ActiveStorage.service_urls_expire_in, captured_options[:expires_in]
  end

  test "qiniu service encodes long upload keys without newlines" do
    key = "ec/skus/2/attachments/1b9f42dd-91eb-490f-85a9-c0f865ffd5cf/robots.txt"
    encoded = ActiveStorage::Service::QiniuService.allocate.send(:encode, key)

    assert_no_match(/\s/, encoded)
    assert_equal Base64.strict_encode64(key).tr("+/", "-_"), encoded
  end
end
