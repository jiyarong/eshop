require "test_helper"

class RawOzon::OzonClientTest < ActiveSupport::TestCase
  test "retries transient SSL errors" do
    client = RawOzon::OzonClient.new("client", "key")
    client.define_singleton_method(:sleep) { |_| }
    attempts = 0

    result = client.send(:with_retry, context: "test") do
      attempts += 1
      raise OpenSSL::SSL::SSLError, "connection interrupted" if attempts == 1

      :ok
    end

    assert_equal :ok, result
    assert_equal 2, attempts
  end

  test "normalizes exhausted connection errors" do
    client = RawOzon::OzonClient.new("client", "key")
    client.define_singleton_method(:sleep) { |_| }

    error = assert_raises(RawOzon::OzonClient::RetryableError) do
      client.send(:with_retry, context: "test") { raise EOFError, "connection closed" }
    end

    assert_equal "connection closed", error.message
  end
end
