require "test_helper"

class ActiveStorageDevelopmentPrefixTest < ActiveSupport::TestCase
  test "prefixes Qiniu blob keys in development" do
    key = "images/#{SecureRandom.hex(8)}.jpg"
    blob = with_rails_environment("development") do
      ActiveStorage::Blob.create!(
        key: key, filename: "example.jpg", content_type: "image/jpeg",
        byte_size: 1, checksum: Digest::MD5.base64digest("x"), service_name: "qiniu"
      )
    end

    assert_equal "development/#{key}", blob.key
  ensure
    ActiveStorage::Blob.where(id: blob&.id).delete_all
  end

  test "does not prefix local storage keys" do
    key = "images/#{SecureRandom.hex(8)}.jpg"
    blob = with_rails_environment("development") do
      ActiveStorage::Blob.create!(
        key: key, filename: "example.jpg", content_type: "image/jpeg",
        byte_size: 1, checksum: Digest::MD5.base64digest("x"), service_name: "local"
      )
    end

    assert_equal key, blob.key
  ensure
    ActiveStorage::Blob.where(id: blob&.id).delete_all
  end

  private

  def with_rails_environment(name)
    original_env = Rails.method(:env)
    environment = ActiveSupport::EnvironmentInquirer.new(name)
    Rails.define_singleton_method(:env) { environment }
    yield
  ensure
    Rails.define_singleton_method(:env, original_env)
  end
end
