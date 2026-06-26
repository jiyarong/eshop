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
    @old_servers = ENV["ERP_AI_MCP_SERVERS"]
  end

  teardown do
    ENV["ERP_AI_MCP_SERVERS"] = @old_servers
  end

  test "builds clients for multiple named MCP servers" do
    ENV["ERP_AI_MCP_SERVERS"] = [
      {
        name: "search",
        endpoint: "https://mcp-search.example.com/mcp",
        bearer_token: "secret-token",
        protocol_version: "2025-06-18"
      },
      {
        name: "docs",
        endpoint: "https://mcp-docs.example.com/mcp"
      }
    ].to_json

    clients = ErpAI::Mcp::ServerRegistry.new(client_class: FakeClient).clients

    assert_equal ["docs", "search"], clients.keys.sort
    assert_equal "https://mcp-search.example.com/mcp", clients.fetch("search").endpoint
    assert_equal "secret-token", clients.fetch("search").bearer_token
    assert_equal "2025-06-18", clients.fetch("docs").protocol_version
  end

  test "returns no clients when configuration is blank" do
    ENV["ERP_AI_MCP_SERVERS"] = ""

    assert_empty ErpAI::Mcp::ServerRegistry.new(client_class: FakeClient).clients
  end

  test "skips invalid names missing endpoints and duplicate names" do
    ENV["ERP_AI_MCP_SERVERS"] = [
      { name: "valid_one", endpoint: "https://valid.example.com/mcp" },
      { name: "Invalid-Name", endpoint: "https://invalid-name.example.com/mcp" },
      { name: "missing_endpoint" },
      { name: "valid_one", endpoint: "https://duplicate.example.com/mcp" }
    ].to_json

    clients = ErpAI::Mcp::ServerRegistry.new(client_class: FakeClient).clients

    assert_equal ["valid_one"], clients.keys
    assert_equal "https://valid.example.com/mcp", clients.fetch("valid_one").endpoint
  end
end
