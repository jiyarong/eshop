require "test_helper"

module Api
  class AuthenticationControllerTest < ActionDispatch::IntegrationTest
    setup do
      @token = SecureRandom.hex(4)
      @user = User.create!(
        email: "api-login-#{@token}@example.com",
        name: "API User",
        password: "password123",
        password_confirmation: "password123"
      )
    end

    teardown do
      @user.avatar.purge if @user&.avatar&.attached?
      UserAccessToken.where(user_id: @user&.id).delete_all
      UserApiKey.where(user_id: @user&.id).delete_all
      User.where(id: @user&.id).destroy_all
    end

    test "login returns a bearer token that authenticates profile requests" do
      create_sub2_api_key

      assert_difference "UserAccessToken.where(user: @user).count", 1 do
        post "/api/login", params: { email: @user.email, password: "password123" }, as: :json
      end

      assert_response :success
      body = response.parsed_body
      raw_token = body.dig("data", "token")
      access_token = UserAccessToken.find_by!(user: @user)

      assert body["success"]
      assert_equal "Bearer", body.dig("data", "token_type")
      assert raw_token.start_with?("api_")
      assert_not_equal raw_token, access_token.token_digest
      assert_equal @user.email, body.dig("data", "profile", "email")

      service = Object.new
      service.define_singleton_method(:entrypoint_url) { "https://sub2.example.com/v1" }
      service.define_singleton_method(:models) { |**| [] }
      with_sub2_service(service) do
        get "/api/profile", headers: bearer_headers(raw_token), as: :json
      end

      assert_response :success
      assert_equal @user.id, response.parsed_body.dig("data", "id")
      assert UserAccessToken.find(access_token.id).last_used_at.present?
    end

    test "login normalizes copied email characters before lookup" do
      create_sub2_api_key

      assert_difference "UserAccessToken.where(user: @user).count", 1 do
        post "/api/login", params: { email: "\u2005，#{@user.email}\u200B", password: "password123" }, as: :json
      end

      assert_response :success
      assert_equal @user.email, response.parsed_body.dig("data", "profile", "email")
    end

    test "login provisions a missing Sub2 API key before LLM configuration is requested" do
      provisioned_api_token = "sk-sub2-#{@token}"
      provisioner_calls = []
      provisioner = lambda do |user:, **|
        provisioner_calls << user.id
        Sub2UserApiKey.create!(
          user: user,
          remote_key_id: "remote-#{@token}",
          encrypted_api_key: Sub2UserApiKey.encrypt(provisioned_api_token),
          name: "eshop-user-#{user.id}"
        )
      end
      service = Object.new
      service.define_singleton_method(:entrypoint_url) { "https://sub2.example.com/v1" }
      service.define_singleton_method(:models) { |api_key:| api_key == provisioned_api_token ? [ "gpt-5" ] : [] }

      with_sub2_provisioner(provisioner) do
        post "/api/login", params: { email: @user.email, password: "password123" }, as: :json
      end

      assert_response :success
      assert_equal [ @user.id ], provisioner_calls
      assert_equal provisioned_api_token, @user.reload.sub2_user_api_key.api_key

      raw_token = response.parsed_body.dig("data", "token")
      with_sub2_service(service) do
        get "/api/profile", headers: bearer_headers(raw_token), as: :json
      end

      assert_response :success
      assert_equal(
        {
          "entrypoint_url" => "https://sub2.example.com/v1",
          "api_token" => provisioned_api_token,
          "models" => [ "gpt-5" ]
        },
        response.parsed_body.dig("data", "llm_config")
      )
    end

    test "login does not issue an access token when Sub2 API key provisioning fails" do
      provisioner = lambda do |**|
        raise Sub2UserApiKeyProvisioner::Error, "remote unavailable"
      end

      assert_no_difference "UserAccessToken.where(user: @user).count" do
        with_sub2_provisioner(provisioner) do
          post "/api/login", params: { email: @user.email, password: "password123" }, as: :json
        end
      end

      assert_response :bad_gateway
      assert_equal "sub2_api_key_provisioning_failed", response.parsed_body["error"]
      assert_nil @user.reload.sub2_user_api_key
    end

    test "login rejects an invalid password and inactive user" do
      assert_no_difference "UserAccessToken.count" do
        post "/api/login", params: { email: @user.email, password: "wrong-password" }, as: :json
      end

      assert_response :unauthorized
      assert_equal "invalid_credentials", response.parsed_body["error"]

      @user.update!(active: false)

      assert_no_difference "UserAccessToken.count" do
        post "/api/login", params: { email: @user.email, password: "password123" }, as: :json
      end

      assert_response :unauthorized
    end

    test "profile requires a valid bearer token" do
      get "/api/profile", as: :json
      assert_response :unauthorized

      get "/api/profile", headers: bearer_headers("api_invalid"), as: :json
      assert_response :unauthorized
    end

    test "profile returns an existing usable API key" do
      existing_api_key, = UserApiKey.generate_for!(@user, name: "Existing")
      raw_token, = UserAccessToken.generate_for!(@user)

      assert_no_difference "UserApiKey.where(user: @user).count" do
        get "/api/profile", headers: bearer_headers(raw_token), as: :json
      end

      assert_response :success
      assert_equal existing_api_key, response.parsed_body.dig("data", "api_key")
    end

    test "profile creates an API key when the user has no usable key" do
      _, revoked_key = UserApiKey.generate_for!(@user, name: "API")
      revoked_key.update!(revoked_at: Time.current)
      raw_token, = UserAccessToken.generate_for!(@user)

      assert_difference "UserApiKey.where(user: @user).count", 1 do
        get "/api/profile", headers: bearer_headers(raw_token), as: :json
      end

      assert_response :success
      api_key = response.parsed_body.dig("data", "api_key")
      assert api_key.start_with?("mcp_")
      assert_equal @user, UserApiKey.authenticate(api_key)
      assert_equal "API 2", @user.api_keys.order(:created_at).last.name
    end

    test "profile returns Sub2 LLM configuration for the current user" do
      api_token = "sk-sub2-#{@token}"
      create_sub2_api_key(api_token: api_token)
      service = Object.new
      requested_api_token = nil
      service.define_singleton_method(:entrypoint_url) { "https://sub2.example.com/v1" }
      service.define_singleton_method(:models) do |api_key:|
        requested_api_token = api_key
        [ "deepseek-v4-flash", "gpt-5" ]
      end
      original_new = Sub2AIService.method(:new)
      Sub2AIService.define_singleton_method(:new) { service }
      raw_token, = UserAccessToken.generate_for!(@user)

      get "/api/profile", headers: bearer_headers(raw_token), as: :json

      assert_response :success
      assert_equal api_token, requested_api_token
      assert_equal(
        {
          "entrypoint_url" => "https://sub2.example.com/v1",
          "api_token" => api_token,
          "models" => [ "deepseek-v4-flash", "gpt-5" ]
        },
        response.parsed_body.dig("data", "llm_config")
      )
    ensure
      Sub2AIService.define_singleton_method(:new, original_new) if original_new
    end

    test "an existing token stops authenticating after the user is deactivated" do
      raw_token, = UserAccessToken.generate_for!(@user)
      @user.update!(active: false)

      get "/api/profile", headers: bearer_headers(raw_token), as: :json

      assert_response :unauthorized
    end

    test "logout destroys only the current access token" do
      raw_token, access_token = UserAccessToken.generate_for!(@user)
      other_raw_token, other_access_token = UserAccessToken.generate_for!(@user)

      assert_difference "UserAccessToken.count", -1 do
        delete "/api/logout", headers: bearer_headers(raw_token), as: :json
      end

      assert_response :success
      assert_not UserAccessToken.exists?(access_token.id)
      assert UserAccessToken.exists?(other_access_token.id)

      get "/api/profile", headers: bearer_headers(raw_token), as: :json
      assert_response :unauthorized

      get "/api/profile", headers: bearer_headers(other_raw_token), as: :json
      assert_response :success
    end

    test "profile updates personal information" do
      raw_token, = UserAccessToken.generate_for!(@user)
      new_email = "api-updated-#{@token}@example.com"

      patch "/api/profile",
        params: { name: "Updated User", email: new_email, time_zone: "Europe/Moscow" },
        headers: bearer_headers(raw_token),
        as: :json

      assert_response :success
      assert_equal "Updated User", response.parsed_body.dig("data", "name")
      assert_equal new_email, @user.reload.email
      assert_equal "Europe/Moscow", @user.time_zone
    end

    test "profile rejects invalid personal information" do
      raw_token, = UserAccessToken.generate_for!(@user)

      patch "/api/profile",
        params: { time_zone: "Invalid/Zone" },
        headers: bearer_headers(raw_token),
        as: :json

      assert_response :unprocessable_entity
      assert response.parsed_body.dig("errors", "time_zone").present?
      assert_equal User::DEFAULT_TIME_ZONE, @user.reload.time_zone
    end

    test "profile changes password after verifying the current password" do
      raw_token, = UserAccessToken.generate_for!(@user)

      patch "/api/profile",
        params: {
          current_password: "password123",
          password: "new-password-123",
          password_confirmation: "new-password-123"
        },
        headers: bearer_headers(raw_token),
        as: :json

      assert_response :success
      assert @user.reload.valid_password?("new-password-123")
      assert_not @user.valid_password?("password123")
    end

    test "wrong current password does not partially update profile" do
      raw_token, = UserAccessToken.generate_for!(@user)

      patch "/api/profile",
        params: {
          name: "Should Not Persist",
          current_password: "wrong-password",
          password: "new-password-123",
          password_confirmation: "new-password-123"
        },
        headers: bearer_headers(raw_token),
        as: :json

      assert_response :unprocessable_entity
      assert response.parsed_body.dig("errors", "current_password").present?
      assert_equal "API User", @user.reload.name
      assert @user.valid_password?("password123")
    end

    test "password confirmation mismatch does not change password" do
      raw_token, = UserAccessToken.generate_for!(@user)

      patch "/api/profile",
        params: {
          current_password: "password123",
          password: "new-password-123",
          password_confirmation: "different-password"
        },
        headers: bearer_headers(raw_token),
        as: :json

      assert_response :unprocessable_entity
      assert response.parsed_body.dig("errors", "password_confirmation").present?
      assert @user.reload.valid_password?("password123")
    end

    test "password confirmation is required" do
      raw_token, = UserAccessToken.generate_for!(@user)

      patch "/api/profile",
        params: { current_password: "password123", password: "new-password-123" },
        headers: bearer_headers(raw_token),
        as: :json

      assert_response :unprocessable_entity
      assert response.parsed_body.dig("errors", "password_confirmation").present?
      assert @user.reload.valid_password?("password123")
    end

    test "profile uploads an avatar" do
      raw_token, = UserAccessToken.generate_for!(@user)
      upload = uploaded_avatar

      patch "/api/profile", params: { avatar: upload }, headers: bearer_headers(raw_token)

      assert_response :success
      assert @user.reload.avatar.attached?
      assert_equal "avatar-#{@token}.png", @user.avatar.filename.to_s
      assert_match %r{/rails/active_storage/blobs/redirect/}, response.parsed_body.dig("data", "avatar_url")
    ensure
      upload&.tempfile&.close!
    end

    private

    def create_sub2_api_key(api_token: "sk-sub2-existing-#{@token}")
      Sub2UserApiKey.create!(
        user: @user,
        remote_key_id: "remote-existing-#{@token}",
        encrypted_api_key: Sub2UserApiKey.encrypt(api_token),
        name: "eshop-#{@user.id}"
      )
    end

    def with_sub2_provisioner(replacement)
      original_call = Sub2UserApiKeyProvisioner.method(:call)
      Sub2UserApiKeyProvisioner.define_singleton_method(:call, replacement)
      yield
    ensure
      Sub2UserApiKeyProvisioner.define_singleton_method(:call, original_call)
    end

    def with_sub2_service(service)
      original_new = Sub2AIService.method(:new)
      Sub2AIService.define_singleton_method(:new) { service }
      yield
    ensure
      Sub2AIService.define_singleton_method(:new, original_new)
    end

    def bearer_headers(raw_token)
      { "Authorization" => "Bearer #{raw_token}" }
    end

    def uploaded_avatar
      tempfile = Tempfile.new([ "avatar-#{@token}", ".png" ])
      tempfile.write("test avatar")
      tempfile.rewind
      Rack::Test::UploadedFile.new(
        tempfile.path,
        "image/png",
        false,
        original_filename: "avatar-#{@token}.png"
      )
    end
  end
end
