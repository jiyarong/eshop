require "test_helper"
require "socket"

class ErpAI::Mcp::TavilyClientTest < ActiveSupport::TestCase
  class FakeRandom
    attr_reader :arguments

    def initialize(*indexes)
      @indexes = indexes
    end

    def rand(length)
      @arguments = length
      @indexes.shift
    end
  end

  setup do
    @requests = []
    @server = TCPServer.new("127.0.0.1", 0)
    @endpoint = "http://127.0.0.1:#{@server.addr[1]}/search"
    @thread = Thread.new { serve_request }
  end

  teardown do
    @server.close
    @thread.join
  end

  test "exposes web_search with a focused Tavily schema" do
    client = build_client

    tool = client.list_tools.first

    assert_equal "web_search", tool.fetch("name")
    assert_equal [ "query" ], tool.fetch("inputSchema").fetch("required")
    assert_equal %w[basic advanced], tool.dig("inputSchema", "properties", "search_depth", "enum")
  end

  test "randomly selects an API key for each search request" do
    random = FakeRandom.new(1, 0)
    client = build_client(random: random)

    client.call_tool("web_search", { "query" => "first" })
    client.call_tool("web_search", { "query" => "second" })

    assert_equal 2, random.arguments
    assert_equal [ "key-two", "key-one" ], @requests.map { |request| request.fetch("api_key") }
    assert_equal [ "first", "second" ], @requests.map { |request| request.fetch("query") }
  end

  test "rejects blank queries before making an HTTP request" do
    client = build_client

    error = assert_raises(ErpAI::Mcp::TavilyClient::McpError) do
      client.call_tool("web_search", { "query" => " " })
    end

    assert_equal "invalid_arguments", error.code
    assert_empty @requests
  end

  private

  def build_client(random: Random)
    ErpAI::Mcp::TavilyClient.new(
      name: "search",
      endpoint: @endpoint,
      api_keys: [ "key-one", "key-two" ],
      random: random
    )
  end

  def serve_request
    2.times do
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

      body = JSON.parse(socket.read(headers.fetch("content-length").to_i))
      @requests << body
      response_body = { "answer" => "answer", "results" => [] }.to_json
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
