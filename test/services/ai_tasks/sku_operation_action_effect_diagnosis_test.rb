require "test_helper"

class AITasks::SkuOperationActionEffectDiagnosisTest < ActiveSupport::TestCase
  class FakeClient
    attr_reader :requests

    def initialize
      @requests = []
    end

    def complete(request)
      @requests << request
      payload = JSON.parse(request.fetch(:messages).sole.fetch(:content))
      action_ids = payload.fetch("target_action_evaluations").map { |evaluation| evaluation.dig("action", "id") }
      {
        content: {
          summary: "广告开启后漏斗指标改善，但仍有同期操作干扰。",
          effectiveness: "positive",
          confidence: "medium",
          events: action_ids.map do |action_id|
            {
              action_id: action_id,
              severity: "info",
              effect: "positive",
              message: "广告开启后的浏览和下单日均值高于操作前。",
              recommendations: [ "继续观察完整 14 天窗口" ]
            }
          end
        }.to_json
      }
    end
  end

  setup do
    @token = SecureRandom.hex(5).upcase
    @as_of_date = Date.new(2026, 8, 3)
    @time_zone = Time.find_zone!("Asia/Shanghai")
    @user = User.create!(
      email: "action-diagnosis-#{@token.downcase}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
    @account = RawWb::SellerAccount.create!(
      name: "Action diagnosis #{@token}",
      api_token: "token-#{@token}",
      company_type: "small"
    )
    @store = Ec::Store.create!(
      platform: "wb",
      store_name: "Action diagnosis #{@token}",
      company_type: "small",
      wb_raw_account_id: @account.id,
      is_active: true
    )
    @sku = Ec::Sku.create!(sku_code: "ACTION-DIAG-#{@token}", product_name: "Action diagnosis")
    @product = Ec::SkuProduct.create!(
      sku: @sku,
      store: @store,
      product_id: "#{800_000_000 + rand(10_000)}"
    )
    @target_actions = [ 30, 14, 7 ].map do |days_ago|
      create_action(@as_of_date - days_ago.days, "sku_adv_on_off")
    end
    @target_action = @target_actions.last
    @other_action = create_action(@as_of_date - 3.days, "listing_content")
    @current_week_action = create_action(@as_of_date, "listing_pricing")
    create_funnel_rows
    @client = FakeClient.new
    @agent_existed = Agent.exists?(code: AITasks::SkuOperationActionEffectDiagnosis::AGENT_CODE)
  end

  teardown do
    Ec::OperationActionDiagnosis.where(sku_id: @sku&.id).destroy_all
    Ec::OperationAction.where(ec_sku_id: @sku&.id).delete_all
    RawWb::SalesFunnelDaily.where(account_id: @account&.id).delete_all
    Ec::SkuProduct.where(id: @product&.id).delete_all
    Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
    Ec::Store.where(id: @store&.id).delete_all
    RawWb::SellerAccount.where(id: @account&.id).delete_all
    Agent.where(code: AITasks::SkuOperationActionEffectDiagnosis::AGENT_CODE).delete_all unless @agent_existed
    User.where(id: @user&.id).delete_all
  end

  test "diagnoses target-date actions, stores recent context, and is idempotent per day" do
    assert_difference "Ec::OperationActionDiagnosis.count", 1 do
      AITasks::SkuOperationActionEffectDiagnosis.run(
        as_of_date: @as_of_date,
        client: @client,
        user: @user
      )
    end

    diagnosis = Ec::OperationActionDiagnosis.find_by!(sku: @sku)
    assert_equal "OperationActionDiagnosis", diagnosis[:type]
    assert_equal "operation_action_effect", diagnosis.data.fetch("diagnosis_kind")
    assert_equal "2026-08-02", diagnosis.data.fetch("analysis_cutoff_date")
    assert_equal "positive", diagnosis.data.fetch("effectiveness")
    assert_equal [ *@target_actions.map(&:id), @other_action.id ], diagnosis.data.fetch("recent_actions").map { |action| action.fetch("id") }
    assert_equal 3, diagnosis.events.size
    event = diagnosis.events.detect { |item| item.details.dig("action", "id") == @target_action.id }
    assert_equal "operation_action_effect", event.event_type
    assert_equal @target_action.id, event.details.dig("action", "id")
    assert_operator event.details.dig("after", "metrics", "views_daily"), :>, event.details.dig("before", "metrics", "views_daily")
    assert_equal [ "继续观察完整 14 天窗口" ], event.details.fetch("recommendations")

    assert_no_difference "Ec::OperationActionDiagnosis.count" do
      AITasks::SkuOperationActionEffectDiagnosis.run(
        as_of_date: @as_of_date,
        client: @client,
        user: @user
      )
    end
    assert_equal 1, @client.requests.size
  end

  private

  def create_action(date, operation_type)
    Ec::OperationAction.create!(
      operation_type: operation_type,
      operated_by_user: @user,
      operated_at: @time_zone.local(date.year, date.month, date.day, 10),
      sku_product: @product,
      sku: @sku,
      store: @store,
      diff_result: {
        "fields" => {
          "advertising_enabled" => { "from" => false, "to" => true }
        }
      },
      record_by_system: true
    )
  end

  def create_funnel_rows
    target_date = @as_of_date - 7.days
    ((target_date - 7.days)..(target_date - 1.day)).each do |date|
      create_funnel_row(date, views: 10, carts: 2, orders: 1)
    end
    ((target_date + 1.day)..(@as_of_date - 1.day)).each do |date|
      create_funnel_row(date, views: 30, carts: 9, orders: 4)
    end
  end

  def create_funnel_row(date, views:, carts:, orders:)
    RawWb::SalesFunnelDaily.create!(
      account: @account,
      stat_date: date,
      nm_id: @product.product_id,
      open_card: views,
      add_to_cart: carts,
      orders: orders,
      orders_sum: orders * 100,
      synced_at: Time.current
    )
  end
end
