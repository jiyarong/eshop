require "test_helper"

class ErpAI::StructuredContentStreamTest < ActiveSupport::TestCase
  test "emits progressively decoded top-level content" do
    contents = []
    stream = ErpAI::StructuredContentStream.new { |content| contents << content }

    [ '{"con', 'tent":"第一行\\n', '第二行 \\"完成\\"', '"}' ].each { |chunk| stream.append(chunk) }

    assert_equal "第一行\n第二行 \"完成\"", contents.last
    assert_operator contents.size, :>=, 2
  end

  test "does not expose tool call payloads as answer content" do
    contents = []
    stream = ErpAI::StructuredContentStream.new { |content| contents << content }

    stream.append('{"tool_calls":[{"name":"search","arguments":{"content":"secret"}}]}')

    assert_empty contents
  end

  test "waits for a complete escaped unicode surrogate pair" do
    contents = []
    stream = ErpAI::StructuredContentStream.new { |content| contents << content }

    stream.append('{"content":"结果 \\uD83D')
    stream.append('\\uDE00"}')

    assert_equal "结果 😀", contents.last
  end
end
