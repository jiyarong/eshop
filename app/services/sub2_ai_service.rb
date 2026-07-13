require "net/http"
require "json"

class Sub2AIService
  AUTH_TOKENS_CACHE_KEY = "sub2_ai/auth_tokens"
  AUTH_TOKENS_CACHE_TTL = 1.week
  GROUPS_CACHE_KEY = "sub2_ai/groups"
  GROUPS_CACHE_TTL = 6.hours

  class Error < StandardError
    attr_reader :http_status, :api_code

    def initialize(message, http_status: nil, api_code: nil)
      @http_status = http_status
      @api_code = api_code
      super(message)
    end
  end

  def initialize(host: ENV["SUB2AI_HOST"] || "https://sub.foresight-soft.com/", cache: Rails.cache)
    @host = host.to_s.chomp("/")
    @cache = cache
  end

  def configured?
    true
  end

  def entrypoint_url
    return if @host.blank?

    "#{@host}/v1"
  end

  def login(force: false)
    email = ENV.fetch('ESHOP_SUB2AI_USER'){'demo@local.com'}
    password = ENV.fetch('ESHOP_SUB2AI_PASSWORD'){'passwd'}

    cached_tokens = @cache.read(AUTH_TOKENS_CACHE_KEY) unless force
    return cached_tokens if access_token_from(cached_tokens).present?

    @cache.delete(AUTH_TOKENS_CACHE_KEY) if force
    cache_auth_tokens(post_json("/api/v1/auth/login", { email: email, password: password }))
  end

  def refresh_access_token(refresh_token:)
    tokens = post_json("/api/v1/auth/refresh", { refresh_token: refresh_token })
    cache_auth_tokens(tokens, fallback_refresh_token: refresh_token)
  end

  def api_keys(access_token:)
    with_access_token_retry(access_token) do |current_access_token|
      get_json("/api/v1/keys", bearer_token: current_access_token)
    end
  end

  def models(api_key:)
    res = get_json("/v1/models", bearer_token: api_key, headers: {accept: "application/json"})
    res.find_all{|x|x['type']=='model'}.map{|x|x['id']}
  end

  def usage(api_key:)
    get_json("/v1/usage", bearer_token: api_key, unwrap_data: false)
  end

  def groups(access_token:)
    with_access_token_retry(access_token) do |current_access_token|
      get_json("/api/v1/groups/available", bearer_token: current_access_token)
    end
  end

  def create_api_key(access_token:, name:, group_id: 3, rate_limit_1d: 0, rate_limit_7d: 0)
    with_access_token_retry(access_token) do |current_access_token|
      post_json("/api/v1/keys", {
        name: name,
        group_id: group_id,
        rate_limit_1d: rate_limit_1d,
        rate_limit_7d: rate_limit_7d
      }, bearer_token: current_access_token)
    end
  end

  def api_key_usage(access_token:, api_key_ids:)
    with_access_token_retry(access_token) do |current_access_token|
      post_json("/api/v1/usage/dashboard/api-keys-usage", {
        api_key_ids: api_key_ids
      }, bearer_token: current_access_token)
    end
  end

  def usage_stats(access_token:, start_date:, end_date:)
    with_access_token_retry(access_token) do |current_access_token|
      get_json(
        "/api/v1/usage/stats",
        params: { start_date: start_date.iso8601, end_date: end_date.iso8601 },
        bearer_token: current_access_token
      )
    end
  end

  private

  def with_access_token_retry(access_token)
    yield access_token
  rescue Error => error
    raise unless unauthorized?(error)

    renewed_access_token = renew_access_token(failed_access_token: access_token)
    begin
      yield renewed_access_token
    rescue Error => retry_error
      raise unless unauthorized?(retry_error)

      yield access_token_from(login(force: true))
    end
  end

  def renew_access_token(failed_access_token:)
    cached_tokens = @cache.read(AUTH_TOKENS_CACHE_KEY)
    cached_access_token = access_token_from(cached_tokens)
    return cached_access_token if cached_access_token.present? && cached_access_token != failed_access_token

    refresh_token = token_from(cached_tokens, "refresh_token")
    return access_token_from(login(force: true)) if refresh_token.blank?

    begin
      refreshed_tokens = refresh_access_token(refresh_token: refresh_token)
    rescue Error => error
      raise unless invalid_refresh_token?(error)

      return access_token_from(login(force: true))
    end
    access_token_from(refreshed_tokens).presence || access_token_from(login(force: true))
  end

  def cache_auth_tokens(tokens, fallback_refresh_token: nil)
    return tokens unless tokens.is_a?(Hash)

    cached_tokens = tokens.deep_dup
    if token_from(cached_tokens, "refresh_token").blank? && fallback_refresh_token.present?
      cached_tokens["refresh_token"] = fallback_refresh_token
    end
    @cache.write(AUTH_TOKENS_CACHE_KEY, cached_tokens, expires_in: AUTH_TOKENS_CACHE_TTL)
    cached_tokens
  end

  def access_token_from(tokens)
    token_from(tokens, "access_token", "token")
  end

  def token_from(tokens, *keys)
    return unless tokens.is_a?(Hash)

    keys.each do |key|
      return tokens[key] if tokens[key].present?
      return tokens[key.to_sym] if tokens[key.to_sym].present?
    end
    nil
  end

  def unauthorized?(error)
    error.http_status == 401 || error.api_code.to_i == 401
  end

  def invalid_refresh_token?(error)
    [ 400, 401, 403 ].include?(error.http_status) || error.api_code.present?
  end

  def get_json(path, params: {}, bearer_token: nil, headers: {}, unwrap_data: true)
    request = Net::HTTP::Get.new(build_uri(path, params))
    apply_headers(request, bearer_token: bearer_token, headers: headers)
    perform_request(request, unwrap_data: unwrap_data)
  end

  def post_json(path, payload, bearer_token: nil, headers: {})
    request = Net::HTTP::Post.new(build_uri(path))
    request["Content-Type"] = "application/json"
    request["accept"] = "application/json"
    apply_headers(request, bearer_token: bearer_token, headers: headers)
    request.body = JSON.generate(payload)
    perform_request(request)
  end

  def apply_headers(request, bearer_token:, headers:)
    request["Authorization"] = "Bearer #{bearer_token}" if bearer_token.present?
    headers.each { |name, value| request[name] = value }
  end

  def build_uri(path, params = {})
    raise Error, "Sub2AI host is not configured" if @host.blank?

    uri = URI("#{@host}#{path}")
    uri.query = URI.encode_www_form(params) if params.present?
    uri
  end

  def perform_request(request, unwrap_data: true)
    uri = request.uri
    response = nil
    Net::HTTP.start(
      uri.hostname,
      uri.port,
      use_ssl: uri.scheme == "https",
      read_timeout: 30
    ) { |http| response = http.request(request) }

    unless response.code.to_i.between?(200, 299)
      raise Error.new("Sub2AI API request failed with HTTP #{response.code}", http_status: response.code.to_i)
    end

    body = JSON.parse(response.body)
    api_code = body["code"]
    unless api_code.to_i == 0
      message = body["message"].presence || "business error #{api_code.inspect}"
      raise Error.new("Sub2AI API request failed: #{message}", http_status: response.code.to_i, api_code: api_code)
    end

    unwrap_data ? body["data"] : body
  rescue JSON::ParserError => error
    raise Error, "Sub2AI API returned invalid JSON: #{error.message}"
  rescue Timeout::Error, SocketError, SystemCallError => error
    raise Error, "Sub2AI API request failed: #{error.message}"
  end
end
