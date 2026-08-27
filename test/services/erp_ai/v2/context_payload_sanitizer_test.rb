require "test_helper"

class ErpAI::V2::ContextPayloadSanitizerTest < ActiveSupport::TestCase
  test "recursively removes raw JSON payload keys without changing business change data" do
    value = {
      "raw_json" => { "large" => true },
      context: [{ before: 1, after: 2, nested_raw_payload: [1, 2], item_payload: { large: true } }]
    }

    assert_equal(
      { context: [{ before: 1, after: 2 }] },
      ErpAI::V2::ContextPayloadSanitizer.call(value)
    )
  end
end
