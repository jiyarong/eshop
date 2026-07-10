require "net/http"
require "json"

class Sub2AIService
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

  def initialize(host: ENV["SUB2AI_HOST"] || "https://sub.foresight-soft.com/")
    @host = host.to_s.chomp("/")
  end

  def configured?
    true
  end

  def entrypoint_url
    return if @host.blank?

    "#{@host}/v1"
  end

  def login
    email = ENV.fetch('ESHOP_SUB2AI_USER'){'demo@local.com'}
    password = ENV.fetch('ESHOP_SUB2AI_PASSWORD'){'passwd'}
    post_json("/api/v1/auth/login", { email: email, password: password })
  end

  def refresh_access_token(refresh_token:)
    post_json("/api/v1/auth/refresh", { refresh_token: refresh_token })
  end

  def api_keys(access_token:)
    get_json("/api/v1/keys", bearer_token: access_token)
  end

  def models(api_key:)
    res = get_json("/v1/models", bearer_token: api_key, headers: {accept: "application/json"})
    res.find_all{|x|x['type']=='model'}.map{|x|x['id']}
  end

  def groups(access_token:)
    get_json("/api/v1/groups/available", bearer_token: access_token)
  end

  def create_api_key(access_token:, name:, group_id: 3, rate_limit_1d: 0, rate_limit_7d: 0)
    post_json("/api/v1/keys", {
      name: name,
      group_id: group_id,
      rate_limit_1d: rate_limit_1d,
      rate_limit_7d: rate_limit_7d
    }, bearer_token: access_token)
  end

  def api_key_usage(access_token:, api_key_ids:)
    post_json("/api/v1/usage/dashboard/api-keys-usage", {
      api_key_ids: api_key_ids
    }, bearer_token: access_token)
  end

  def usage_stats(access_token:, start_date:, end_date:)
    get_json(
      "/api/v1/usage/stats",
      params: { start_date: start_date.iso8601, end_date: end_date.iso8601 },
      bearer_token: access_token
    )
  end

  private

  def get_json(path, params: {}, bearer_token: nil, headers: {})
    request = Net::HTTP::Get.new(build_uri(path, params))
    apply_headers(request, bearer_token: bearer_token, headers: headers)
    perform_request(request)
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

  def perform_request(request)
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

    body["data"]
  rescue JSON::ParserError => error
    raise Error, "Sub2AI API returned invalid JSON: #{error.message}"
  rescue Timeout::Error, SocketError, SystemCallError => error
    raise Error, "Sub2AI API request failed: #{error.message}"
  end
end
