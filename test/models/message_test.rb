require "test_helper"

class MessageTest < ActiveSupport::TestCase
  test "reads normalized token usage including zero cache hits" do
    message = Message.new(usage: { input_tokens: 100, output_tokens: 25, cached_tokens: 0, total_tokens: 125 })

    assert_equal({ "input_tokens" => 100, "output_tokens" => 25, "cached_tokens" => 0, "total_tokens" => 125 }, message.token_usage)
  end

  test "reads chat completion usage without counting cache hits twice" do
    message = Message.new(usage: {
      prompt_tokens: 100, completion_tokens: 25,
      prompt_tokens_details: { cached_tokens: 80 }
    })

    assert_equal({ "input_tokens" => 100, "output_tokens" => 25, "cached_tokens" => 80, "total_tokens" => 125 }, message.token_usage)
  end

  test "reads response API cache details" do
    message = Message.new(usage: {
      input_tokens: 100, output_tokens: 25,
      input_tokens_details: { cached_tokens: 80 }, total_tokens: 125
    })

    assert_equal 80, message.token_usage.fetch("cached_tokens")
    assert_equal 125, message.token_usage.fetch("total_tokens")
  end

  test "reads DeepSeek cache hits" do
    message = Message.new(usage: {
      prompt_tokens: 100, completion_tokens: 25,
      prompt_cache_hit_tokens: 80, prompt_cache_miss_tokens: 20
    })

    assert_equal 80, message.token_usage.fetch("cached_tokens")
    assert_equal 125, message.token_usage.fetch("total_tokens")
  end

  test "keeps reported totals and does not invent missing breakdowns" do
    message = Message.new(usage: { total_tokens: 125 })

    assert_equal({ "total_tokens" => 125 }, message.token_usage)
    assert_empty Message.new.token_usage
  end

  test "does not calculate a total from an incomplete breakdown" do
    message = Message.new(usage: { prompt_tokens: 100 })

    assert_equal({ "input_tokens" => 100 }, message.token_usage)
  end
end
