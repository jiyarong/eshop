require 'net/http'
require 'json'

module RawOzon
  class OzonClient
    BASE_URL     = 'https://api-seller.ozon.ru'
    MAX_RETRIES  = 3
    OPEN_TIMEOUT = 10
    READ_TIMEOUT = 30

    class RetryableError < StandardError
      attr_reader :retry_after, :rate_limit_remaining, :request_id
      def initialize(msg, retry_after: nil, rate_limit_remaining: nil, request_id: nil)
        super(msg)
        @retry_after = retry_after
        @rate_limit_remaining = rate_limit_remaining
        @request_id = request_id
      end
    end

    class ApiError < StandardError; end

    def initialize(client_id, api_key)
      @client_id = client_id
      @api_key   = api_key
    end

    attr_reader :last_response_headers

    def get(path, params = {}, headers: {})
      uri = URI("#{BASE_URL}#{path}")
      uri.query = URI.encode_www_form(params.compact) unless params.empty?

      with_retry(context: "GET #{path}") do
        req = Net::HTTP::Get.new(uri)
        set_headers(req, headers)
        perform(uri, req)
      end
    end

    def post(path, body = {}, headers: {})
      uri = URI("#{BASE_URL}#{path}")

      with_retry(context: "POST #{path}") do
        req      = Net::HTTP::Post.new(uri)
        req.body = body.to_json
        set_headers(req, headers)
        perform(uri, req)
      end
    end

    def download(path)
      uri = URI(path.to_s.match?(%r{\Ahttps?://}) ? path : "#{BASE_URL}#{path}")

      with_retry(context: "GET #{path}") do
        req = Net::HTTP::Get.new(uri)
        set_headers(req) if uri.host == URI(BASE_URL).host
        resp = Net::HTTP.start(uri.host, uri.port,
                               use_ssl: true,
                               open_timeout: OPEN_TIMEOUT,
                               read_timeout: READ_TIMEOUT) { |http| http.request(req) }
        handle_download_response(resp, uri.path)
      end
    end

    private

    def set_headers(req, extra = {})
      req['Client-Id']     = @client_id
      req['Api-Key']       = @api_key
      req['Content-Type']  = 'application/json'
      extra.to_h.each { |key, value| req[key.to_s] = value.to_s if value.present? }
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
      rescue RetryableError, Timeout::Error, SocketError, EOFError, IOError,
        SystemCallError, OpenSSL::SSL::SSLError => e
        retries += 1
        if retries > MAX_RETRIES
          raise if e.is_a?(RetryableError)

          raise RetryableError, e.message
        end
        wait = (e.retry_after if e.respond_to?(:retry_after)) || (2**retries)
        Rails.logger.warn "[OzonClient] #{context} — retry #{retries}/#{MAX_RETRIES} in #{wait}s (#{e.message})"
        sleep wait
        retry
      end
    end

    def handle_response(resp, path)
      @last_response_headers = {
        "request_id" => resp["X-Request-Id"].presence || resp["Request-Id"].presence,
        "retry_after" => resp["Retry-After"].presence,
        "item_retry_after" => resp["Item-Retry-After"].presence,
        "item_rate_limit_remaining" => resp["Item-Rate-Limit-Remaining"].presence
      }.compact
      code = resp.code.to_i
      case code
      when 200..299
        body = resp.body.presence
        body ? JSON.parse(body) : {}
      when 429
        wait = resp['Item-Retry-After']&.to_i || resp['Retry-After']&.to_i || 10
        raise RetryableError.new(
          "429 rate-limited on #{path}",
          retry_after: wait,
          rate_limit_remaining: resp['Item-Rate-Limit-Remaining'],
          request_id: @last_response_headers["request_id"]
        )
      when 500..599
        raise RetryableError.new("#{code} server error on #{path}")
      else
        raise ApiError, "#{code} on #{path}: #{resp.body.to_s.encode('UTF-8', invalid: :replace, undef: :replace, replace: '').truncate(300)}"
      end
    rescue JSON::ParserError => error
      raise ApiError, "Malformed JSON response on #{path}: #{error.message}"
    end

    def handle_download_response(resp, path)
      code = resp.code.to_i
      case code
      when 200..299
        { body: resp.body, content_type: resp["Content-Type"].to_s.split(";").first }
      when 429
        wait = resp["Item-Retry-After"]&.to_i || resp["Retry-After"]&.to_i || 10
        raise RetryableError.new(
          "429 rate-limited on #{path}",
          retry_after: wait,
          rate_limit_remaining: resp["Item-Rate-Limit-Remaining"],
          request_id: @last_response_headers&.dig("request_id")
        )
      when 500..599
        raise RetryableError.new("#{code} server error on #{path}")
      else
        raise ApiError, "#{code} on #{path}: attachment download failed"
      end
    end
  end
end
