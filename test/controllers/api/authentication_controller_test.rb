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
      User.where(id: @user&.id).destroy_all
    end

    test "login returns a bearer token that authenticates profile requests" do
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

      get "/api/profile", headers: bearer_headers(raw_token), as: :json

      assert_response :success
      assert_equal @user.id, response.parsed_body.dig("data", "id")
      assert UserAccessToken.find(access_token.id).last_used_at.present?
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

    test "profile returns Sub2 LLM configuration for the current user" do
      api_token = "sk-sub2-#{@token}"
      Sub2UserApiKey.create!(
        user: @user,
        remote_key_id: "remote-#{@token}",
        encrypted_api_key: Sub2UserApiKey.encrypt(api_token),
        name: "eshop-#{@user.id}"
      )
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
        response.parsed_body.dig("data", "llm_configs")
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
