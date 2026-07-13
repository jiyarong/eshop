require "test_helper"

module Api
  class ProfileUsageControllerTest < ActionDispatch::IntegrationTest
    setup do
      @token = SecureRandom.hex(6)
      @user = User.create!(
        email: "profile-usage-#{@token}@example.com",
        password: "password123",
        password_confirmation: "password123"
      )
      @raw_token, = UserAccessToken.generate_for!(@user)
    end

    teardown do
      Sub2UserApiKey.where(user: @user).delete_all
      UserAccessToken.where(user: @user).delete_all
      User.where(id: @user.id).delete_all
    end

    test "returns usage from Sub2 for the current user's API key" do
      api_key = "sk-sub2-#{@token}"
      Sub2UserApiKey.create!(
        user: @user,
        remote_key_id: "remote-#{@token}",
        encrypted_api_key: Sub2UserApiKey.encrypt(api_key),
        name: "eshop-#{@user.id}"
      )
      usage = { "balance" => 12.5, "usage" => { "total" => { "requests" => 7 } } }
      service = Object.new
      requested_api_key = nil
      service.define_singleton_method(:usage) do |api_key:|
        requested_api_key = api_key
        usage
      end

      with_sub2_service(service) do
        get "/api/v1/profile/usage", headers: bearer_headers, as: :json
      end

      assert_response :success
      assert_equal api_key, requested_api_key
      assert_equal({ "success" => true, "data" => usage }, response.parsed_body)
    end

    test "requires a local bearer token" do
      get "/api/v1/profile/usage", as: :json

      assert_response :unauthorized
    end

    test "rejects a user without a Sub2 API key" do
      get "/api/v1/profile/usage", headers: bearer_headers, as: :json

      assert_response :unprocessable_entity
      assert_equal "sub2_api_key_not_configured", response.parsed_body["error"]
    end

    test "returns bad gateway when Sub2 is unavailable" do
      Sub2UserApiKey.create!(
        user: @user,
        remote_key_id: "remote-#{@token}",
        encrypted_api_key: Sub2UserApiKey.encrypt("sk-sub2-#{@token}"),
        name: "eshop-#{@user.id}"
      )
      service = Object.new
      service.define_singleton_method(:usage) do |**|
        raise Sub2AIService::Error.new("upstream unavailable", http_status: 503)
      end

      with_sub2_service(service) do
        get "/api/v1/profile/usage", headers: bearer_headers, as: :json
      end

      assert_response :bad_gateway
      assert_equal "sub2_usage_unavailable", response.parsed_body["error"]
    end

    private

    def bearer_headers
      { "Authorization" => "Bearer #{@raw_token}" }
    end

    def with_sub2_service(service)
      original_new = Sub2AIService.method(:new)
      Sub2AIService.define_singleton_method(:new) { service }
      yield
    ensure
      Sub2AIService.define_singleton_method(:new, original_new)
    end
  end
end
