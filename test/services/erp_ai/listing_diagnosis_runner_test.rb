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

  test "runs listing-audit with weekly funnel and search term data for two complete weeks" do
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
    listing_context_argument = nil
    listing_image_blob = Object.new
    listing_context.define_singleton_method(:call) do |sku_product:|
      listing_context_argument = sku_product
      "# Listing context for #{sku_product.sku_code}"
    end
    listing_context.define_singleton_method(:image_attachment) do |sku_product:|
      listing_context_argument = sku_product
      file = Struct.new(:blob) do
        def attached? = true
      end.new(listing_image_blob)
      Struct.new(:file).new(file)
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
    search_query_arguments = []
    requested_search_sku_codes = []
    search_terms_query = Class.new do
      define_singleton_method(:new) do |**arguments|
        search_query_arguments << arguments
        first_week = arguments.fetch(:period_from) == Date.new(2026, 8, 24)
        Object.new.tap do |query|
          query.define_singleton_method(:terms_for) do |sku_code|
            requested_search_sku_codes << sku_code
            [
              {
                keyword: "summer dress",
                search_volume: first_week ? 320 : 80,
                avg_position: first_week ? 12.5 : 22.5,
                median_position: nil,
                views: first_week ? 48 : 12,
                orders: 3
              }
            ]
          end
        end
      end
    end

    result = ErpAI::ListingDiagnosisRunner.new(
      suggestion: @suggestion,
      listing_context: listing_context,
      sales_funnel_context: funnel_context,
      search_terms_query: search_terms_query,
      runner_factory: runner_factory,
      today: Date.new(2026, 9, 7)
    ).run

    assert result.completed?
    assert_equal "## Result\n\nImprove the title.", result.content
    assert_equal "listing-audit", result.conversation.agent.code
    assert_equal "2026-08-24", ask_arguments.dig(:time_range, :from)
    assert_equal "2026-09-06", ask_arguments.dig(:time_range, :to)
    assert_includes ask_arguments.fetch(:data_summary), "# 当前诊断目标"
    assert_includes ask_arguments.fetch(:data_summary), "product_id: #{@sku_product.product_id}"
    assert_includes ask_arguments.fetch(:data_summary), "# Listing context for #{@sku.sku_code}"
    assert_includes ask_arguments.fetch(:data_summary), '"hits_view": 120'
    assert_includes ask_arguments.fetch(:data_summary), "# 近期搜索关键词"
    assert_includes ask_arguments.fetch(:data_summary), '"keyword": "summer dress"'
    assert_includes ask_arguments.fetch(:data_summary), '"period_from": "2026-08-24"'
    assert_includes ask_arguments.fetch(:data_summary), '"period_to": "2026-08-30"'
    assert_includes ask_arguments.fetch(:data_summary), '"period_from": "2026-08-31"'
    assert_includes ask_arguments.fetch(:data_summary), '"period_to": "2026-09-06"'
    assert_includes ask_arguments.fetch(:data_summary), '"search_volume": 320'
    assert_includes ask_arguments.fetch(:data_summary), '"search_volume": 80'
    assert_includes ask_arguments.fetch(:data_summary), '"avg_position": 12.5'
    assert_includes ask_arguments.fetch(:data_summary), '"avg_position": 22.5'
    assert_includes ask_arguments.fetch(:data_summary), '"views": 48'
    assert_includes ask_arguments.fetch(:data_summary), '"views": 12'
    refute_includes ask_arguments.fetch(:data_summary), '"orders": 3'
    assert_equal 2, ask_arguments.fetch(:data_summary).scan('"keyword": "summer dress"').size
    assert_equal [ listing_image_blob ], ask_arguments.fetch(:images)
    assert_equal @sku_product, listing_context_argument
    assert_equal @sku, funnel_arguments.fetch(:sku)
    assert_equal @sku_product, funnel_arguments.fetch(:sku_product)
    assert_equal Date.new(2026, 8, 24), funnel_arguments.fetch(:period_from)
    assert_equal Date.new(2026, 9, 6), funnel_arguments.fetch(:period_to)
    assert_equal "ozon:#{@account.id}", funnel_arguments.fetch(:store_options).sole.fetch(:ref)
    assert_equal 2, search_query_arguments.size
    assert_equal [
      Date.new(2026, 8, 24), Date.new(2026, 8, 31)
    ], search_query_arguments.pluck(:period_from)
    assert_equal [ @sku.sku_code ] * 2, requested_search_sku_codes
    search_query_arguments.each do |arguments|
      assert_equal "ozon", arguments.fetch(:platform)
      assert_equal @store, arguments.fetch(:store)
      assert_equal [ @sku.sku_code ], arguments.fetch(:sku_codes)
      assert_equal arguments.fetch(:period_from).end_of_week(:monday), arguments.fetch(:period_to)
    end
  end

  test "marks the diagnosis failed when the agent call raises" do
    runner_factory = lambda do |**|
      Object.new.tap do |runner|
        runner.define_singleton_method(:ask) { |**| raise RuntimeError, "AI unavailable" }
      end
    end
    listing_context = Object.new
    listing_context.define_singleton_method(:call) { |**| "listing" }
    listing_context.define_singleton_method(:image_attachment) { |**| nil }
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
