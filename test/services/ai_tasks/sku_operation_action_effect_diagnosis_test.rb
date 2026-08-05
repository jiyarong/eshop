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
      action_ids = payload.fetch("action_timeline").filter_map do |action|
        action.fetch("id") if action.fetch("diagnosis_target")
      end
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
              message: "广告开启后的浏览和下单周均值高于操作前。",
              recommendations: [ "继续观察后续完整自然周" ]
            }
          end
        }.to_json
      }
    end
  end

  class QuietClient
    def complete(_request)
      {
        content: {
          summary: "近期操作未见需要特别关注的经营变化。",
          effectiveness: "inconclusive",
          confidence: "low",
          events: []
        }.to_json
      }
    end
  end

  setup do
    @token = SecureRandom.hex(5).upcase
    @as_of_date = Date.new(2026, 8, 4)
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
    @target_actions = [ Date.new(2026, 7, 1), Date.new(2026, 7, 22), Date.new(2026, 7, 29) ].map do |date|
      create_action(date, "sku_adv_on_off")
    end
    @target_action = @target_actions.second
    @target_action.update!(
      operation_type: "listing_content",
      diff_result: {
        "fields" => {
          "images" => {
            "added" => [
              "https://example.com/images/1.webp",
              "https://example.com/images/2.webp",
              "https://example.com/video/index.m3u8"
            ],
            "removed" => [],
            "primary_from" => nil,
            "primary_to" => "https://example.com/images/1.webp"
          },
          "title" => { "from" => "Old title", "to" => "New title" },
          "brand" => { "from" => nil, "to" => "New brand" }
        },
        "platform" => "wb",
        "attribution" => "assigned_operator"
      }
    )
    @target_actions.last.update!(
      operation_type: "listing_pricing",
      diff_result: {
        "fields" => {
          "price" => { "from" => "100.0", "to" => "90.0" }
        }
      }
    )
    @other_action = create_action(Date.new(2026, 6, 24), "listing_content")
    @other_action.update!(
      operation_type: "manual_note",
      diff_result: { "note" => "已调整补货节奏，观察本周销量" }
    )
    @too_old_action = create_action(Date.new(2026, 5, 20), "listing_specification")
    @current_week_action = create_action(Date.new(2026, 8, 3), "listing_pricing")
    create_funnel_rows
    create_inventory_snapshot(Date.new(2026, 7, 12), book_stock: 100, platform_stock: 50, inbound_quantity: 10)
    create_inventory_snapshot(Date.new(2026, 7, 26), book_stock: 80, platform_stock: 35, inbound_quantity: 5)
    stub_weekly_profit_reports
    @client = FakeClient.new
    @agent_existed = Agent.exists?(code: AITasks::SkuOperationActionEffectDiagnosis::AGENT_CODE)
  end

  teardown do
    Ec::OperationActionDiagnosis.where(sku_id: @sku&.id).destroy_all
    Message.where(conversation: Conversation.where(user: @user)).delete_all
    Conversation.where(user: @user).delete_all
    Ec::OperationAction.where(ec_sku_id: @sku&.id).delete_all
    Ec::Snapshot.where(snapshot_type: Ec::InventorySnapshot.snapshot_type, sku_id: @sku&.id).delete_all
    RawWb::SalesFunnelDaily.where(account_id: @account&.id).delete_all
    Ec::SkuProduct.where(id: @product&.id).delete_all
    Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
    Ec::Store.where(id: @store&.id).delete_all
    RawWb::SellerAccount.where(id: @account&.id).delete_all
    WeeklyProfitReports::ReportQueryRunner.define_singleton_method(:run, @original_profit_report_run)
    Agent.where(code: AITasks::SkuOperationActionEffectDiagnosis::AGENT_CODE).delete_all unless @agent_existed
    User.where(id: @user&.id).delete_all
  end

  test "diagnoses actions using an ordered action timeline and independent weekly metric series" do
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
    assert_equal 5, diagnosis.data.fetch("observation_weeks")
    assert_equal 10, diagnosis.data.fetch("max_lookback_weeks")
    assert_equal "monday", diagnosis.data.fetch("week_starts_on")
    assert_equal "weekly_average", diagnosis.data.fetch("metric_granularity")
    assert_equal "positive", diagnosis.data.fetch("effectiveness")
    assert_equal [ @other_action.id ], diagnosis.data.fetch("recent_actions").map { |action| action.fetch("id") }
    assert_equal 3, diagnosis.events.size
    event = diagnosis.events.detect { |item| item.details.dig("action", "id") == @target_action.id }
    assert_equal "operation_action_effect", event.event_type
    assert_equal @target_action.id, event.details.dig("action", "id")
    assert_equal 2, event.details.dig("action", "weeks_ago")
    expected_changes = [ "新增 图片（3项）", "新增 主图", "修改 标题", "新增 品牌" ]
    assert_equal expected_changes.sort, event.details.dig("action", "changes").sort
    assert_equal "2026-07-06", event.details.dig("periods", "before", "from")
    assert_equal "2026-07-19", event.details.dig("periods", "before", "to")
    assert_equal "2026-07-20", event.details.dig("periods", "after", "from")
    assert_equal "2026-08-02", event.details.dig("periods", "after", "to")
    assert_equal 2, event.details.dig("periods", "before", "weeks")
    assert_equal 70.0, event.details.dig("metrics", "funnel_views_weekly", "before")
    assert_equal 210.0, event.details.dig("metrics", "funnel_views_weekly", "after")
    assert_equal 3.0, event.details.dig("metrics", "profit_sales_quantity_weekly", "before")
    assert_equal 7.0, event.details.dig("metrics", "profit_sales_quantity_weekly", "after")
    assert_equal 100.0, event.details.dig("metrics", "sku_inventory_book_stock_weekly", "before")
    assert_equal 80.0, event.details.dig("metrics", "sku_inventory_book_stock_weekly", "after")
    assert_not event.details.dig("metrics", "funnel_cancellations_weekly")
    assert_equal [ "继续观察后续完整自然周" ], event.details.fetch("recommendations")
    conversation = event.conversation
    assert conversation
    assert_equal @user, conversation.user
    assert_equal "sku_operation_actions", conversation.module_name
    assert_equal [ "user", "assistant" ], conversation.messages.order(:created_at, :id).pluck(:role)
    assert_includes conversation.messages.first.content, "event_policy"
    assert_includes conversation.messages.last.content, "漏斗指标改善"
    assert_equal conversation.id, diagnosis.events.map(&:conversation_id).uniq.sole

    oldest_event = diagnosis.events.detect { |item| item.details.dig("action", "id") == @target_actions.first.id }
    assert_equal "2026-05-25", oldest_event.details.dig("periods", "before", "from")
    assert_equal "2026-08-02", oldest_event.details.dig("periods", "after", "to")

    request_payload = JSON.parse(@client.requests.sole.fetch(:messages).sole.fetch(:content))
    action_timeline = request_payload.fetch("action_timeline")
    assert_equal [ @other_action.id, *@target_actions.map(&:id) ], action_timeline.map { |action| action.fetch("id") }
    assert_equal [ false, true, true, true ], action_timeline.map { |action| action.fetch("diagnosis_target") }
    target_action_payload = action_timeline.find { |action| action.fetch("id") == @target_action.id }
    assert_equal expected_changes.sort, target_action_payload.fetch("changes").sort
    pricing_action_payload = action_timeline.find { |action| action.fetch("id") == @target_actions.last.id }
    assert_equal [ "修改 售价：100.0 → 90.0" ], pricing_action_payload.fetch("changes")
    note_action_payload = action_timeline.find { |action| action.fetch("id") == @other_action.id }
    assert_equal [ "已调整补货节奏，观察本周销量" ], note_action_payload.fetch("notes")
    assert_not note_action_payload.key?("note")

    weekly_metrics = request_payload.fetch("weekly_metrics")
    assert_equal 10, weekly_metrics.fetch("weeks").size
    assert_equal "2026-05-25", weekly_metrics.dig("weeks", 0, "start")
    assert_equal "2026-08-02", weekly_metrics.dig("weeks", 9, "end")
    assert_equal (10).downto(1).to_a, weekly_metrics.fetch("weeks").map { |week| week.fetch("weeks_ago") }
    store_metrics = weekly_metrics.dig("stores", @store.id.to_s)
    assert_equal "BYN", store_metrics.fetch("currency")
    assert_equal [ 0, 0, 0, 0, 0, 0, 6, 0, 14, 0 ], store_metrics.dig("profit_report", "sales_quantity")
    assert_equal [ 0, 0, 0, 0, 0, 0, 12, 0, 28, 0 ], store_metrics.dig("profit_report", "advertising_cost")
    assert_equal [ nil, nil, nil, nil, nil, nil, "2026-07-12", nil, "2026-07-26", nil ], store_metrics.dig("inventory", "snapshot_date")
    assert_equal [ nil, nil, nil, nil, nil, nil, 50, nil, 35, nil ], store_metrics.dig("inventory", "platform_stock")
    assert_equal [ nil, nil, nil, nil, nil, nil, 100, nil, 80, nil ], weekly_metrics.dig("inventory_snapshots", "sku", "book_stock")
    assert_equal [ nil, nil, nil, nil, nil, nil, 70.0, 70.0, 210.0, 210.0 ], weekly_metrics.dig("sales_funnel", "wb", "views")
    assert_equal [ 0, 0, 0, 0, 0, 0, 7, 7, 7, 7 ], weekly_metrics.dig("sales_funnel", "wb", "funnel_coverage_days")
    assert_equal "natural_week", request_payload.fetch("metric_granularity")
    assert_not request_payload.key?("target_action_evaluations")
    assert_not request_payload.key?("recent_actions")
    field_definitions = request_payload.fetch("field_definitions")
    assert_equal "广告费用；正数表示费用，负数表示冲回", field_definitions.dig("weekly_metrics", "profit_report", "advertising_cost")
    assert_equal "该周采用的最新库存快照日期", field_definitions.dig("weekly_metrics", "inventory", "snapshot_date")
    assert_equal "销售漏斗数据源记录的下单金额，不替代周利润报表销售收入", field_definitions.dig("weekly_metrics", "sales_funnel", "revenue")
    assert_equal "运营备注的具体文字列表", field_definitions.dig("action_timeline", "notes")
    assert_includes @client.requests.sole.fetch(:system_prompt), "profit_report 来自周利润报表"
    assert_not_includes request_payload.to_json, "https://"
    assert_not_includes diagnosis.data.to_json, "https://"

    assert_no_difference "Ec::OperationActionDiagnosis.count" do
      AITasks::SkuOperationActionEffectDiagnosis.run(
        as_of_date: @as_of_date + 1.day,
        client: @client,
        user: @user
      )
    end
    assert_equal 1, @client.requests.size
  end

  test "does not persist routine actions omitted by the AI" do
    diagnosis = AITasks::SkuOperationActionEffectDiagnosis.run(
      as_of_date: @as_of_date,
      client: QuietClient.new,
      user: @user
    ).sole

    assert_empty diagnosis.events
    assert_equal "近期操作未见需要特别关注的经营变化。", diagnosis.data.fetch("summary")
    assert_equal 1, Conversation.where(user: @user).count
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
    (Date.new(2026, 7, 6)..Date.new(2026, 7, 19)).each do |date|
      create_funnel_row(date, views: 10, carts: 2, orders: 1)
    end
    (Date.new(2026, 7, 20)..Date.new(2026, 8, 2)).each do |date|
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

  def create_inventory_snapshot(date, book_stock:, platform_stock:, inbound_quantity:)
    Ec::Snapshot.create!(
      snapshot_type: Ec::InventorySnapshot.snapshot_type,
      snapshot_date: date,
      sku: @sku,
      content: {
        overview: {
          book_stock: book_stock,
          platform_stock: platform_stock,
          platform_inbound_stock: inbound_quantity,
          available_stock: book_stock - platform_stock - inbound_quantity,
          out_of_stock: platform_stock.zero?
        },
        distribution: {
          levels: [
            {
              store_id: @store.id,
              platform: "wb",
              account_id: @account.id,
              fulfillment_type: "fbw",
              quantity: platform_stock
            },
            {
              store_id: @store.id,
              platform: "wb",
              account_id: @account.id,
              fulfillment_type: "inbound",
              quantity: inbound_quantity
            }
          ]
        }
      }
    )
  end

  def stub_weekly_profit_reports
    @original_profit_report_run = WeeklyProfitReports::ReportQueryRunner.method(:run)
    requests = @profit_report_requests = []
    weekly_values = {
      Date.new(2026, 7, 6) => { sales_quantity: 6, advertising_cost: 12, after_tax_profit: 60 },
      Date.new(2026, 7, 20) => { sales_quantity: 14, advertising_cost: 28, after_tax_profit: 140 }
    }
    WeeklyProfitReports::ReportQueryRunner.define_singleton_method(:run) do |params:, today:|
      requests << { params: params, today: today }
      week_start = Date.iso8601(params.fetch(:from_date))
      values = weekly_values.fetch(
        week_start,
        { sales_quantity: 0, advertising_cost: 0, after_tax_profit: 0 }
      )
      {
        rows: [
          {
            sales_qty: values.fetch(:sales_quantity),
            return_qty: 0,
            net_qty: values.fetch(:sales_quantity),
            retail_amount: values.fetch(:sales_quantity) * 100,
            settlement: values.fetch(:sales_quantity) * 80,
            delivery: values.fetch(:sales_quantity) * 5,
            storage: 0,
            ad: values.fetch(:advertising_cost),
            goods_cost: values.fetch(:sales_quantity) * 20,
            pre_tax: values.fetch(:after_tax_profit),
            tax: 0,
            after_tax: values.fetch(:after_tax_profit)
          }
        ]
      }
    end
  end
end
