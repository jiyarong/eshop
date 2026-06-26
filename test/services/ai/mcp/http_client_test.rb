require "test_helper"
require "socket"

module ErpAI
  module Mcp
  end
end

class ErpAI::Mcp::HttpClientTest < ActiveSupport::TestCase
  setup do
    @requests = []
    @server = TCPServer.new("127.0.0.1", 0)
    @endpoint = "http://127.0.0.1:#{@server.addr[1]}/mcp"
    @thread = Thread.new { serve_requests }
  end

  teardown do
    @server.close
    @thread.join
  end

  test "sends initialize request with MCP headers and bearer token" do
    client = ErpAI::Mcp::HttpClient.new(
      name: "search",
      endpoint: @endpoint,
      bearer_token: "secret",
      protocol_version: "2025-06-18"
    )

    result = client.initialize_session

    assert_equal "fake", result.fetch("serverInfo").fetch("name")
    request = @requests.last
    body = request.fetch(:body)
    assert_equal "initialize", body.fetch("method")
    assert_equal "application/json", request.fetch(:headers).fetch("content-type")
    assert_equal "application/json, text/event-stream", request.fetch(:headers).fetch("accept")
    assert_equal "2025-06-18", request.fetch(:headers).fetch("mcp-protocol-version")
    assert_equal "Bearer secret", request.fetch(:headers).fetch("authorization")
  end

  test "lists tools and calls tools over JSON-RPC" do
    client = ErpAI::Mcp::HttpClient.new(name: "search", endpoint: @endpoint)

    tools = client.list_tools
    result = client.call_tool("web_search", { "query" => "sku" })

    assert_equal "web_search", tools.first.fetch("name")
    assert_equal "result for sku", result.fetch("content").first.fetch("text")
    assert_equal ["tools/list", "tools/call"], @requests.last(2).map { |request| request.fetch(:body).fetch("method") }
  end

  private

  def serve_requests
    loop do
      socket = @server.accept
      request_line = socket.gets
      break if request_line.nil?

      headers = {}
      while (line = socket.gets)
        line = line.strip
        break if line.empty?

        key, value = line.split(":", 2)
        headers[key.downcase] = value.strip
      end

      body_text = socket.read(headers.fetch("content-length").to_i)
      body = JSON.parse(body_text)
      @requests << { request_line: request_line, headers: headers, body: body }
      result =
        case body.fetch("method")
        when "initialize"
          { protocolVersion: "2025-06-18", serverInfo: { name: "fake" } }
        when "tools/list"
          { tools: [{ name: "web_search", description: "Search" }] }
        when "tools/call"
          { content: [{ type: "text", text: "result for #{body.dig('params', 'arguments', 'query')}" }] }
        end
      response_body = { jsonrpc: "2.0", id: body.fetch("id"), result: result }.to_json
      socket.write "HTTP/1.1 200 OK\r\n"
      socket.write "Content-Type: application/json\r\n"
      socket.write "Content-Length: #{response_body.bytesize}\r\n"
      socket.write "Connection: close\r\n"
      socket.write "\r\n"
      socket.write response_body
      socket.close
    end
  rescue IOError
    nil
  end
end
