require 'net/http'
require 'json'

module RawOzon
  class OzonClient
    BASE_URL     = 'https://api-seller.ozon.ru'
    MAX_RETRIES  = 3
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

    def initialize(client_id, api_key)
      @client_id = client_id
      @api_key   = api_key
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

    def set_headers(req)
      req['Client-Id']     = @client_id
      req['Api-Key']       = @api_key
      req['Content-Type']  = 'application/json'
    end

    def perform(uri, req)
      resp = Net::HTTP.start(uri.host, uri.port,
                             use_ssl: true,
                             open_timeout: OPEN_TIMEOUT,
                             read_timeout: READ_TIMEOUT) { |h| h.request(req) }
      handle_response(resp, uri.path)
    end

    def with_retry(context:)
      retries = 0
      begin
        yield
      rescue RetryableError => e
        retries += 1
        raise if retries > MAX_RETRIES
        wait = e.retry_after || (2**retries)
        Rails.logger.warn "[OzonClient] #{context} — retry #{retries}/#{MAX_RETRIES} in #{wait}s (#{e.message})"
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
        raise ApiError, "#{code} on #{path}: #{resp.body.to_s.encode('UTF-8', invalid: :replace, undef: :replace, replace: '').truncate(300)}"
      end
    end
  end
end
