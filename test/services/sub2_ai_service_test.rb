require "test_helper"

class Sub2AIServiceTest < ActiveSupport::TestCase
  test "login caches access and refresh tokens" do
    cache = ActiveSupport::Cache::MemoryStore.new
    service = Sub2AIService.new(host: "https://sub2.example.com", cache: cache)
    requests = 0
    tokens = {
      "access_token" => "access-token",
      "refresh_token" => "refresh-token"
    }
    service.define_singleton_method(:post_json) do |*, **|
      requests += 1
      tokens
    end

    assert_equal tokens, service.login
    assert_equal tokens, service.login
    assert_equal tokens, cache.read(Sub2AIService::AUTH_TOKENS_CACHE_KEY)
    assert_equal 1, requests
    assert_equal 1.week, Sub2AIService::AUTH_TOKENS_CACHE_TTL
  end

  test "refreshes an invalid access token and retries the request" do
    cache = ActiveSupport::Cache::MemoryStore.new
    cache.write(Sub2AIService::AUTH_TOKENS_CACHE_KEY, {
      "access_token" => "expired-access-token",
      "refresh_token" => "refresh-token"
    })
    service = Sub2AIService.new(host: "https://sub2.example.com", cache: cache)
    requested_tokens = []
    refresh_request = nil
    service.define_singleton_method(:get_json) do |*, bearer_token:, **|
      requested_tokens << bearer_token
      raise Sub2AIService::Error.new("unauthorized", http_status: 401) if bearer_token == "expired-access-token"

      [ { "id" => 1 } ]
    end
    service.define_singleton_method(:post_json) do |path, payload, **|
      refresh_request = { path: path, payload: payload }
      {
        "access_token" => "refreshed-access-token",
        "refresh_token" => "rotated-refresh-token"
      }
    end

    assert_equal [ { "id" => 1 } ], service.api_keys(access_token: "expired-access-token")
    assert_equal [ "expired-access-token", "refreshed-access-token" ], requested_tokens
    assert_equal "/api/v1/auth/refresh", refresh_request[:path]
    assert_equal({ refresh_token: "refresh-token" }, refresh_request[:payload])
    assert_equal "refreshed-access-token", cache.read(Sub2AIService::AUTH_TOKENS_CACHE_KEY)["access_token"]
    assert_equal "rotated-refresh-token", cache.read(Sub2AIService::AUTH_TOKENS_CACHE_KEY)["refresh_token"]
  end

  test "logs in again when the refresh token is invalid" do
    cache = ActiveSupport::Cache::MemoryStore.new
    cache.write(Sub2AIService::AUTH_TOKENS_CACHE_KEY, {
      "access_token" => "expired-access-token",
      "refresh_token" => "expired-refresh-token"
    })
    service = Sub2AIService.new(host: "https://sub2.example.com", cache: cache)
    requested_tokens = []
    auth_requests = []
    service.define_singleton_method(:get_json) do |*, bearer_token:, **|
      requested_tokens << bearer_token
      raise Sub2AIService::Error.new("unauthorized", http_status: 401) if bearer_token == "expired-access-token"

      [ { "id" => 1 } ]
    end
    service.define_singleton_method(:post_json) do |path, *, **|
      auth_requests << path
      if path == "/api/v1/auth/refresh"
        raise Sub2AIService::Error.new("invalid refresh token", http_status: 401)
      end

      {
        "access_token" => "new-login-access-token",
        "refresh_token" => "new-login-refresh-token"
      }
    end

    assert_equal [ { "id" => 1 } ], service.api_keys(access_token: "expired-access-token")
    assert_equal [ "/api/v1/auth/refresh", "/api/v1/auth/login" ], auth_requests
    assert_equal [ "expired-access-token", "new-login-access-token" ], requested_tokens
    assert_equal "new-login-access-token", cache.read(Sub2AIService::AUTH_TOKENS_CACHE_KEY)["access_token"]
    assert_equal "new-login-refresh-token", cache.read(Sub2AIService::AUTH_TOKENS_CACHE_KEY)["refresh_token"]
  end

  test "does not log in again when token refresh fails with a server error" do
    cache = ActiveSupport::Cache::MemoryStore.new
    cache.write(Sub2AIService::AUTH_TOKENS_CACHE_KEY, {
      "access_token" => "expired-access-token",
      "refresh_token" => "refresh-token"
    })
    service = Sub2AIService.new(host: "https://sub2.example.com", cache: cache)
    auth_requests = []
    service.define_singleton_method(:get_json) do |*, **|
      raise Sub2AIService::Error.new("unauthorized", http_status: 401)
    end
    service.define_singleton_method(:post_json) do |path, *, **|
      auth_requests << path
      raise Sub2AIService::Error.new("server error", http_status: 500)
    end

    error = assert_raises(Sub2AIService::Error) do
      service.api_keys(access_token: "expired-access-token")
    end

    assert_equal 500, error.http_status
    assert_equal [ "/api/v1/auth/refresh" ], auth_requests
  end

  test "requests usage stats with ISO dates and the access token" do
    service = Sub2AIService.new(host: "https://sub2.example.com")
    captured = nil
    service.define_singleton_method(:get_json) do |path, params:, bearer_token:|
      captured = { path:, params:, bearer_token: }
      { "total_requests" => 2 }
    end

    result = service.usage_stats(
      access_token: "access-token",
      start_date: Date.new(2026, 7, 9),
      end_date: Date.new(2026, 7, 10)
    )

    assert_equal({ "total_requests" => 2 }, result)
    assert_equal "/api/v1/usage/stats", captured[:path]
    assert_equal({ start_date: "2026-07-09", end_date: "2026-07-10" }, captured[:params])
    assert_equal "access-token", captured[:bearer_token]
  end
end
