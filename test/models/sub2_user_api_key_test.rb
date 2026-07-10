require "test_helper"

class Sub2UserApiKeyTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(6)
    @user = User.create!(
      email: "sub2-key-#{@token}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
  end

  teardown do
    Sub2UserApiKey.where(user: @user).delete_all
    User.where(id: @user.id).delete_all
  end

  test "encrypts the Sub2 API key and enforces one key per user" do
    binding = Sub2UserApiKey.create!(
      user: @user,
      remote_key_id: "remote-#{@token}",
      encrypted_api_key: Sub2UserApiKey.encrypt("sk-sub2-#{@token}"),
      name: "eshop-user-#{@user.id}"
    )

    assert_equal "sk-sub2-#{@token}", binding.api_key
    assert_not_includes binding.encrypted_api_key, @token
    assert_not Sub2UserApiKey.new(
      user: @user,
      remote_key_id: "other-#{@token}",
      encrypted_api_key: Sub2UserApiKey.encrypt("other-key"),
      name: "other"
    ).valid?
  end
end
