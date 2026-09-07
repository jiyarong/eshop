require "test_helper"

class ErpAI::ListingDiagnosisRunnerTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(5).upcase
    @user = User.create!(
      email: "listing-diagnosis-runner-#{@token.downcase}@example.com",
      password: "password123",
      password_confirmation: "password123",
      time_zone: "Asia/Shanghai"
    )
    @agent = Agent.create!(
      code: "listing-audit",
      name: "Listing Audit",
      system_prompt: "Audit the supplied listing.",
      model_id: "fake-model",
      temperature: 0.2,
      tools: []
    )
    @account = RawOzon::SellerAccount.create!(
      company_name: "Listing audit #{@token}",
      client_id: "listing-audit-#{@token}",
      api_key: @token,
      company_type: "small"
    )
    @store = Ec::Store.create!(
      platform: "ozon",
      store_name: "Listing audit #{@token}",
      company_type: "small",
      ozon_raw_account_id: @account.id
    )
    @sku = Ec::Sku.create!(sku_code: "LISTING-AUDIT-#{@token}", product_name: "Listing audit")
    @sku_product = Ec::SkuProduct.create!(
      sku: @sku,
      store: @store,
      product_id: "542#{@token.hex % 1_000_000}",
      platform_sku_id: "942#{@token.hex % 1_000_000}",
      product_name: "Listing audit product"
    )
    @suggestion = @sku_product.ai_suggestions.create!(
      suggestion_type: Ec::AISuggestion::LISTING_AUDIT_TYPE,
      submitted_by: @user
    )
  end

  teardown do
    Conversation.where(user_id: @user&.id).find_each(&:destroy!)
    Ec::AISuggestion.where(submitted_by: @user).delete_all
    @sku_product&.destroy!
    Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
    @store&.destroy!
    @account&.destroy!
    @agent&.destroy!
    User.where(id: @user&.id).delete_all
  end

  test "runs listing-audit with listing context and four complete weeks of store funnel data" do
    ask_arguments = nil
    runner_factory = lambda do |agent:, user:|
      assert_equal @agent, agent
      assert_equal @user, user

      Object.new.tap do |runner|
        runner.define_singleton_method(:ask) do |**arguments|
          ask_arguments = arguments
          conversation = agent.conversations.create!(user: user)
          conversation.messages.create!(role: "assistant", content: "## Result\n\nImprove the title.")
          conversation
        end
      end
    end
    listing_context = Object.new
    listing_context.define_singleton_method(:call) do |sku_code:|
      "# Listing context for #{sku_code}"
    end
    funnel_arguments = nil
    funnel_context = Class.new do
      define_singleton_method(:new) do |**arguments|
        funnel_arguments = arguments
        Object.new.tap do |context|
          context.define_singleton_method(:call) { [ { stores: [ { data: [ { hits_view: 120 } ] } ] } ] }
        end
      end
    end

    result = ErpAI::ListingDiagnosisRunner.new(
      suggestion: @suggestion,
      listing_context: listing_context,
      sales_funnel_context: funnel_context,
      runner_factory: runner_factory,
      today: Date.new(2026, 9, 7)
    ).run

    assert result.completed?
    assert_equal "## Result\n\nImprove the title.", result.content
    assert_equal "listing-audit", result.conversation.agent.code
    assert_equal "2026-08-10", ask_arguments.dig(:time_range, :from)
    assert_equal "2026-09-06", ask_arguments.dig(:time_range, :to)
    assert_includes ask_arguments.fetch(:data_summary), "# 当前诊断目标"
    assert_includes ask_arguments.fetch(:data_summary), "product_id: #{@sku_product.product_id}"
    assert_includes ask_arguments.fetch(:data_summary), "# Listing context for #{@sku.sku_code}"
    assert_includes ask_arguments.fetch(:data_summary), '"hits_view": 120'
    assert_equal @sku, funnel_arguments.fetch(:sku)
    assert_equal Date.new(2026, 8, 10), funnel_arguments.fetch(:period_from)
    assert_equal Date.new(2026, 9, 6), funnel_arguments.fetch(:period_to)
    assert_equal "ozon:#{@account.id}", funnel_arguments.fetch(:store_options).sole.fetch(:ref)
  end

  test "marks the diagnosis failed when the agent call raises" do
    runner_factory = lambda do |**|
      Object.new.tap do |runner|
        runner.define_singleton_method(:ask) { |**| raise RuntimeError, "AI unavailable" }
      end
    end
    listing_context = Object.new
    listing_context.define_singleton_method(:call) { |**| "listing" }
    funnel_context = Class.new do
      define_singleton_method(:new) do |**|
        Object.new.tap { |context| context.define_singleton_method(:call) { [] } }
      end
    end

    error = assert_raises(RuntimeError) do
      ErpAI::ListingDiagnosisRunner.new(
        suggestion: @suggestion,
        listing_context: listing_context,
        sales_funnel_context: funnel_context,
        runner_factory: runner_factory,
        today: Date.new(2026, 9, 7)
      ).run
    end

    assert_equal "AI unavailable", error.message
    assert @suggestion.reload.failed?
    assert_equal "AI unavailable", @suggestion.error_message
    assert @suggestion.started_at
    assert @suggestion.completed_at
  end

  test "rejects suggestions outside the listing audit workflow without changing them" do
    other_type = @sku_product.ai_suggestions.create!(
      suggestion_type: "product_copy",
      submitted_by: @user
    )
    other_target = Ec::AISuggestion.create!(
      suggestable: @sku,
      suggestion_type: Ec::AISuggestion::LISTING_AUDIT_TYPE,
      submitted_by: @user
    )

    [ other_type, other_target ].each do |suggestion|
      error = assert_raises(ArgumentError) do
        ErpAI::ListingDiagnosisRunner.new(suggestion: suggestion).run
      end

      assert_equal "invalid_listing_audit_suggestion", error.message
      assert suggestion.reload.pending?
      assert_nil suggestion.error_message
    end
  end
end
