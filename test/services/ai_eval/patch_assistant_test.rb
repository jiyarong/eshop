require "test_helper"

class AiEvalPatchAssistantTest < ActiveSupport::TestCase
  test "uses a tool free client and only returns an unapproved proposal" do
    request = nil
    client = Object.new
    client.define_singleton_method(:complete) do |value|
      request = value
      { content: { patches: [], oracle: {}, summary: "Draft", approved: true, status: "approved" } }
    end
    agent = Agent.new(model_id: "eval-model", temperature: 0.1)
    result = AiEval::PatchAssistant.new(client: client).call(documents: { "v3/base_context.json" => {} }, instruction: "模拟缺失", agent: agent)
    assert_equal [], request[:tools]
    assert_equal true, request[:allow_raw_json]
    assert_not result.key?("approved")
    assert_not result.key?("status")
  end
end
