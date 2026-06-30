require "test_helper"

module ErpAI
  module Mcp
  end
end

class ErpAI::Mcp::ServerRegistryTest < ActiveSupport::TestCase
  class FakeClient
    attr_reader :name, :endpoint, :bearer_token, :protocol_version

    def initialize(name:, endpoint:, bearer_token: nil, protocol_version: "2025-06-18")
      @name = name
      @endpoint = endpoint
      @bearer_token = bearer_token
      @protocol_version = protocol_version
    end
  end

  setup do
    @config_file = Tempfile.new(["mcp_servers", ".yml"])
  end

  teardown do
    @config_file.close
    @config_file.unlink
  end

  test "builds clients from environment scoped YAML config" do
    write_config(<<~YAML)
      test:
        - name: search
          endpoint: https://mcp-search.example.com/mcp
          bearer_token: secret-token
          protocol_version: "2025-06-18"
        - name: docs
          endpoint: https://mcp-docs.example.com/mcp
    YAML

    clients = registry.clients

    assert_equal ["docs", "search"], clients.keys.sort
    assert_equal "https://mcp-search.example.com/mcp", clients.fetch("search").endpoint
    assert_equal "secret-token", clients.fetch("search").bearer_token
    assert_equal "2025-06-18", clients.fetch("docs").protocol_version
  end

  test "returns no clients when configuration is blank" do
    write_config("")

    assert_empty registry.clients
  end

  test "skips invalid names missing endpoints and duplicate names" do
    write_config(<<~YAML)
      test:
        - name: valid_one
          endpoint: https://valid.example.com/mcp
        - name: Invalid-Name
          endpoint: https://invalid-name.example.com/mcp
        - name: missing_endpoint
        - name: valid_one
          endpoint: https://duplicate.example.com/mcp
    YAML

    clients = registry.clients

    assert_equal ["valid_one"], clients.keys
    assert_equal "https://valid.example.com/mcp", clients.fetch("valid_one").endpoint
  end

  test "tracks per server MCP tool allowlists from YAML config" do
    write_config(<<~YAML)
      test:
        - name: search
          endpoint: https://search.example.com/mcp
          tools:
            - web_search
            - fetch_page
        - name: docs
          endpoint: https://docs.example.com/mcp
    YAML

    filters = registry.tool_filters

    assert_equal ["fetch_page", "web_search"], filters.fetch("search").sort
    assert_nil filters.fetch("docs")
  end

  private

  def registry
    ErpAI::Mcp::ServerRegistry.new(config_path: @config_file.path, client_class: FakeClient)
  end

  def write_config(content)
    @config_file.write(content)
    @config_file.rewind
  end
end
