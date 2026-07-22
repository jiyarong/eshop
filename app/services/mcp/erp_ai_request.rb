module Mcp
  class ErpAIRequest
    ALLOWED_METHODS = %w[get post put patch delete].freeze
    FORWARDED_HEADER_NAMES = %w[accept accept-language x-request-id].freeze
    RESPONSE_HEADER_NAMES = %w[content-type location].freeze
    MAX_BODY_BYTES = 100_000

    def initialize(current_user:, bearer_token:)
      @current_user = current_user
      @bearer_token = bearer_token.to_s
    end

    def call(args)
      method = args.fetch("method", "get").to_s.downcase
      return error("method is not allowed") unless ALLOWED_METHODS.include?(method)

      uri = parse_url(args["url"])
      return uri if uri.is_a?(Hash)

      path = normalized_path(uri)
      route_error = validate_route(path, method)
      return route_error if route_error

      response = request_app(
        method: method,
        path: path_with_query(method, path, uri.query, args["params"]),
        params: args["params"],
        headers: args["headers"].to_h
      )

      response_payload(response)
    end

    private

    attr_reader :current_user, :bearer_token

    def parse_url(value)
      url = value.to_s.strip
      return error("url is required") if url.blank?

      uri = URI.parse(url)
      return error("only app-relative /ai/... URLs are allowed") if uri.scheme.present? || uri.host.present?

      uri
    rescue URI::InvalidURIError
      error("url is invalid")
    end

    def normalized_path(uri)
      path = uri.path.presence || "/"
      path.start_with?("/") ? path : "/#{path}"
    end

    def validate_route(path, method)
      return error("only /ai/... URLs are allowed") unless path.start_with?("/ai/")

      route = Rails.application.routes.recognize_path(path, method: method)
      controller = route.fetch(:controller).to_s
      return error("only ErpAI controllers are allowed") unless controller.start_with?("erp_ai/")

      nil
    rescue ActionController::RoutingError
      error("route is not found")
    end

    def request_app(method:, path:, params:, headers:)
      Rack::MockRequest.new(Rails.application).request(
        method.upcase,
        path,
        rack_env(method, params, headers)
      )
    end

    def rack_env(method, params, headers)
      env = forwarded_headers(headers)
      env["HTTP_AUTHORIZATION"] = "Bearer #{bearer_token}" if bearer_token.present?
      env["HTTP_ACCEPT"] ||= "application/json"
      return env if method == "get"

      env.merge(
        "CONTENT_TYPE" => "application/json",
        input: JSON.generate(params.to_h)
      )
    end

    def forwarded_headers(headers)
      headers.each_with_object({}) do |(name, value), env|
        normalized = name.to_s.downcase
        next unless FORWARDED_HEADER_NAMES.include?(normalized)

        env[rack_header_name(normalized)] = value.to_s
      end
    end

    def rack_header_name(name)
      return "HTTP_ACCEPT" if name == "accept"

      "HTTP_#{name.tr("-", "_").upcase}"
    end

    def path_with_query(method, path, original_query, params)
      query_parts = []
      query_parts << original_query if original_query.present?
      query_parts << Rack::Utils.build_nested_query(params.to_h) if %w[get delete].include?(method) && params.present?
      return path if query_parts.empty?

      "#{path}?#{query_parts.join("&")}"
    end

    def response_payload(response)
      body = truncate_body(response.body.to_s)
      {
        success: response.status < 400,
        status: response.status,
        headers: response_headers(response.headers),
        body: parsed_body(body.fetch(:text), response.headers["content-type"]),
        truncated: body.fetch(:truncated)
      }
    end

    def truncate_body(text)
      bytes = text.byteslice(0, MAX_BODY_BYTES)
      {
        text: bytes,
        truncated: text.bytesize > MAX_BODY_BYTES
      }
    end

    def parsed_body(text, content_type)
      return JSON.parse(text) if content_type.to_s.include?("json") && text.present?

      text
    rescue JSON::ParserError
      text
    end

    def response_headers(headers)
      headers.each_with_object({}) do |(name, value), result|
        normalized = name.to_s.downcase
        result[name] = value if RESPONSE_HEADER_NAMES.include?(normalized)
      end
    end

    def error(message)
      {
        success: false,
        error: message
      }
    end
  end
end
