require 'net/http'
require 'json'
require 'csv'

module RawOzon
  class PerformanceClient
    BASE_URL     = 'https://api-performance.ozon.ru'
    MAX_RETRIES  = 5
    OPEN_TIMEOUT = 10
    READ_TIMEOUT = 30

    class RetryableError < StandardError
      attr_reader :retry_after
      def initialize(msg, retry_after: nil)
        super(msg)
        @retry_after = retry_after
      end
    end

    class ApiError < StandardError; end

    def initialize(client_id, client_secret)
      @client_id     = client_id
      @client_secret = client_secret
      @token         = nil
      @token_expires_at = Time.at(0)
    end

    def get(path, params = {})
      uri = URI("#{BASE_URL}#{path}")
      uri.query = URI.encode_www_form(params.compact) unless params.empty?
      with_retry(context: "GET #{path}") do
        req = Net::HTTP::Get.new(uri)
        set_headers(req)
        perform(uri, req)
      end
    end

    def get_csv(path, params = {})
      uri = URI("#{BASE_URL}#{path}")
      uri.query = URI.encode_www_form(params.compact) unless params.empty?
      with_retry(context: "GET CSV #{path}") do
        req = Net::HTTP::Get.new(uri)
        set_headers(req)
        resp = http_start(uri) { |h| h.request(req) }
        raise ApiError, "#{resp.code} on #{path}: #{resp.body.to_s.truncate(300)}" unless resp.code.to_i == 200
        resp.body
      end
    end

    def post(path, body = {})
      uri = URI("#{BASE_URL}#{path}")
      with_retry(context: "POST #{path}") do
        req      = Net::HTTP::Post.new(uri)
        req.body = body.to_json
        set_headers(req)
        perform(uri, req)
      end
    end

    private

    def token
      return @token if @token && Time.current < @token_expires_at - 60
      fetch_token
    end

    def fetch_token
      uri = URI("#{BASE_URL}/api/client/token")
      req = Net::HTTP::Post.new(uri)
      req['Content-Type'] = 'application/json'
      req.body = { client_id: @client_id, client_secret: @client_secret, grant_type: 'client_credentials' }.to_json
      resp = http_start(uri) { |h| h.request(req) }
      raise ApiError, "Token fetch failed: #{resp.code} #{resp.body}" unless resp.code.to_i == 200
      data = JSON.parse(resp.body)
      @token = data['access_token']
      @token_expires_at = Time.current + data.fetch('expires_in', 1800).to_i.seconds
      @token
    end

    def set_headers(req)
      req['Authorization'] = "Bearer #{token}"
      req['Content-Type']  = 'application/json'
    end

    def perform(uri, req)
      resp = http_start(uri) { |h| h.request(req) }
      handle_response(resp, uri.path)
    end

    def http_start(uri, &block)
      Net::HTTP.start(uri.host, uri.port,
                      use_ssl: true,
                      open_timeout: OPEN_TIMEOUT,
                      read_timeout: READ_TIMEOUT, &block)
    end

    def with_retry(context:)
      retries = 0
      begin
        yield
      rescue RetryableError => e
        retries += 1
        raise if retries > MAX_RETRIES
        wait = [e.retry_after || 30, 30 * retries].max
        Rails.logger.warn "[PerformanceClient] #{context} — retry #{retries}/#{MAX_RETRIES} in #{wait}s"
        sleep wait
        retry
      end
    end

    def handle_response(resp, path)
      code = resp.code.to_i
      case code
      when 200..299
        body = resp.body.presence
        body ? JSON.parse(body) : {}
      when 429
        wait = resp['Retry-After']&.to_i || 10
        raise RetryableError.new("429 rate-limited on #{path}", retry_after: wait)
      when 500..599
        raise RetryableError.new("#{code} server error on #{path}")
      else
        raise ApiError, "#{code} on #{path}: #{resp.body.to_s.truncate(300)}"
      end
    end
  end
end
