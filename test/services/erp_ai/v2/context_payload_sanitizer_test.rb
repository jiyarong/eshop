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

  test "normalizes decimals only when requested" do
    value = { whole: BigDecimal("2.00"), fraction: BigDecimal("1.25") }

    assert_instance_of BigDecimal, ErpAI::V2::ContextPayloadSanitizer.call(value).fetch(:fraction)
    assert_equal({ whole: 2, fraction: 1.25 }, ErpAI::V2::ContextPayloadSanitizer.call(value, normalize_numbers: true))
  end
end
