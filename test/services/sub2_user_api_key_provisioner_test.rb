require "test_helper"

class Sub2UserApiKeyProvisionerTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(6)
    @user = User.create!(
      email: "sub2-provision-#{@token}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
  end

  teardown do
    Sub2UserApiKey.where(user: @user).delete_all
    User.where(id: @user.id).delete_all
  end

  test "logs in, creates a remote key, and saves the encrypted binding" do
    calls = []
    token = @token
    service = Object.new
    service.define_singleton_method(:login) { { "access_token" => "admin-token" } }
    service.define_singleton_method(:create_api_key) do |access_token:, name:|
      calls << { access_token:, name: }
      { "id" => "remote-#{token}", "key" => "sk-sub2-#{token}", "name" => name }
    end

    binding = Sub2UserApiKeyProvisioner.call(user: @user, service: service)

    assert_equal [{ access_token: "admin-token", name: "eshop-user-#{@user.id}" }], calls
    assert_equal "remote-#{@token}", binding.remote_key_id
    assert_equal "sk-sub2-#{@token}", binding.api_key
    assert_not_includes binding.encrypted_api_key, "sk-sub2"
  end

  test "rejects a response without an API key secret" do
    token = @token
    service = Object.new
    service.define_singleton_method(:login) { { "access_token" => "admin-token" } }
    service.define_singleton_method(:create_api_key) do |**|
      { "id" => "remote-#{token}" }
    end

    assert_raises(Sub2UserApiKeyProvisioner::Error) do
      Sub2UserApiKeyProvisioner.call(user: @user, service: service)
    end
    assert_nil @user.sub2_user_api_key
  end
end
