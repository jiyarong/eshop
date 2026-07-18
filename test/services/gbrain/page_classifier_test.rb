require "test_helper"
require "ostruct"

class Gbrain::PageClassifierTest < ActiveSupport::TestCase
  class FakeClient
    attr_reader :request

    def initialize(content: nil, error: nil)
      @content = content
      @error = error
    end

    def complete(request)
      @request = request
      raise @error if @error

      { content: @content, usage: {} }
    end
  end

  setup do
    @token = SecureRandom.hex(6)
    @agent = OpenStruct.new(
      model_id: "deepseek-v4-flash",
      temperature: 0.1,
      system_prompt: "Return strict JSON"
    )
  end

  test "classifies content with the fixed DeepSeek model and preserves normalized metadata" do
    client = FakeClient.new(content: JSON.generate(valid_payload))
    classifier = Gbrain::PageClassifier.new(client: client, agent: @agent, today: Date.new(2026, 7, 18))

    result = classifier.classify("  原始运营资料  ")

    assert_equal "deepseek-v4-flash", client.request.fetch(:model)
    assert_equal false, client.request.fetch(:thinking_enabled)
    assert_equal [], client.request.fetch(:tools)
    assert_equal [ { role: "user", content: "原始运营资料" } ], client.request.fetch(:messages)
    assert_equal "2026-07-18", result.fetch("reviewed_at")
    assert_equal "2026-10-18", result.fetch("review_after")
    assert_equal [ "platform/ozon", "country/ru" ], result.fetch("tags")
    assert_equal "运营资料结论", result.fetch("summary")
    assert_not result.key?("content")
  end

  test "accepts a JSON response wrapped in a code fence" do
    content = "```json\n#{JSON.generate(valid_payload)}\n```"

    result = Gbrain::PageClassifier.new(
      client: FakeClient.new(content: content),
      agent: @agent,
      today: Date.new(2026, 7, 18)
    ).classify("原始资料")

    assert_equal "notes/ai-#{@token}", result.fetch("slug")
  end

  test "rejects blank input before calling the provider" do
    client = FakeClient.new(content: JSON.generate(valid_payload))

    assert_raises(Gbrain::PageClassifier::InvalidInput) do
      Gbrain::PageClassifier.new(client: client, agent: @agent).classify("  ")
    end
    assert_nil client.request
  end

  test "rejects malformed or incomplete model output" do
    malformed = Gbrain::PageClassifier.new(client: FakeClient.new(content: "not json"), agent: @agent)
    incomplete = Gbrain::PageClassifier.new(client: FakeClient.new(content: { title: "Only title" }.to_json), agent: @agent)

    assert_raises(Gbrain::PageClassifier::InvalidResponse) { malformed.classify("资料") }
    assert_raises(Gbrain::PageClassifier::InvalidResponse) { incomplete.classify("资料") }
  end

  test "rejects model output with an invalid list shape" do
    payload = valid_payload.merge(tags: "platform/ozon")
    classifier = Gbrain::PageClassifier.new(client: FakeClient.new(content: payload.to_json), agent: @agent)

    assert_raises(Gbrain::PageClassifier::InvalidResponse) { classifier.classify("资料") }
  end

  test "wraps provider failures without exposing the provider error" do
    classifier = Gbrain::PageClassifier.new(
      client: FakeClient.new(error: StandardError.new("secret provider detail")),
      agent: @agent
    )

    error = assert_raises(Gbrain::PageClassifier::ProviderError) { classifier.classify("资料") }
    assert_not_includes error.message, "secret provider detail"
  end

  private

  def valid_payload
    {
      title: "运营资料",
      page_type: "note",
      subtype: "operations-note",
      slug: "notes/ai-#{@token}",
      aliases: [ "运营说明" ],
      tags: [ "platform/ozon", "country/ru" ],
      platform: "ozon",
      country: "RU",
      region_scope: [],
      category_scope: [],
      effective_date: nil,
      source_tier: "third-party",
      confidence: "medium",
      summary: "运营资料结论"
    }
  end
end
