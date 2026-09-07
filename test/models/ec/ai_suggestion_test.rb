require "test_helper"

class Ec::AISuggestionTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(5).upcase
    @user = User.create!(
      email: "ai-suggestion-model-#{@token.downcase}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
    @account = RawWb::SellerAccount.create!(
      name: "AI suggestion #{@token}",
      api_token: @token,
      company_type: "small"
    )
    @store = Ec::Store.create!(
      platform: "wb",
      store_name: "AI suggestion #{@token}",
      company_type: "small",
      wb_raw_account_id: @account.id
    )
    @sku = Ec::Sku.create!(sku_code: "AI-SUGGESTION-#{@token}")
    @sku_product = Ec::SkuProduct.create!(
      sku: @sku,
      store: @store,
      product_id: (800_000_000 + @token.hex % 10_000_000).to_s
    )
  end

  teardown do
    Ec::AISuggestion.where(submitted_by: @user).delete_all
    @sku_product&.destroy!
    Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
    @store&.destroy!
    @account&.destroy!
    User.where(id: @user&.id).delete_all
  end

  test "stores a typed suggestion against a polymorphic target" do
    suggestion = Ec::AISuggestion.create!(
      suggestable: @sku,
      suggestion_type: "sku_copy_review",
      submitted_by: @user
    )

    assert_equal @sku, suggestion.suggestable
    assert_equal "Ec::Sku", suggestion.suggestable_type
    assert_equal "sku_copy_review", suggestion.suggestion_type
  end

  test "requires content or error details for terminal states" do
    completed = @sku_product.ai_suggestions.new(
      suggestion_type: Ec::AISuggestion::LISTING_AUDIT_TYPE,
      submitted_by: @user,
      status: :completed
    )
    failed = @sku_product.ai_suggestions.new(
      suggestion_type: Ec::AISuggestion::LISTING_AUDIT_TYPE,
      submitted_by: @user,
      status: :failed
    )

    assert_not completed.valid?
    assert completed.errors[:content].any?
    assert_not failed.valid?
    assert failed.errors[:error_message].any?
  end

  test "allows only one active suggestion of each type per target" do
    @sku_product.ai_suggestions.create!(
      suggestion_type: Ec::AISuggestion::LISTING_AUDIT_TYPE,
      submitted_by: @user
    )

    assert_raises ActiveRecord::RecordNotUnique do
      @sku_product.ai_suggestions.create!(
        suggestion_type: Ec::AISuggestion::LISTING_AUDIT_TYPE,
        submitted_by: @user,
        status: :running
      )
    end

    assert_difference -> { @sku_product.ai_suggestions.count }, 1 do
      @sku_product.ai_suggestions.create!(
        suggestion_type: "pricing_review",
        submitted_by: @user
      )
    end
  end
end
