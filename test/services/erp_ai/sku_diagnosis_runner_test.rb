require "test_helper"

class ErpAI::SkuDiagnosisRunnerTest < ActiveSupport::TestCase
  class SavingClient
    attr_reader :requests

    def initialize
      @requests = []
    end

    def complete(request)
      @requests << request
      return { content: "Saved", tool_calls: [] } if requests.size.even?

      question = request.fetch(:messages).first.fetch(:content)
      sku_code = question[/当前 SKU：([^\n]+)/, 1]
      rule_id = question[/当前子规则 ID：(\d+)/, 1].to_i
      {
        content: nil,
        tool_calls: [{
          id: "save-#{requests.size}", name: "save_sku_event",
          arguments: {
            sku_code: sku_code, sub_agent_id: rule_id, severity: "warning",
            event_type: "stock_risk", message: "Stock issue: sales increased", advise: "Replenish"
          }
        }]
      }
    end
  end

  class FakeSnapshotFetcher
    attr_reader :calls

    def initialize
      @calls = []
    end

    def fetch(sku_code, snapshot_date:)
      calls << { sku_code: sku_code, snapshot_date: snapshot_date }
      {
        "sku_code" => sku_code,
        "period" => {
          "from" => (snapshot_date.beginning_of_week(:monday) - 1.week).iso8601,
          "to" => (snapshot_date.beginning_of_week(:monday) - 1.day).iso8601,
          "as_of" => snapshot_date.iso8601
        },
        "categories" => Ec::SkuContextSnapshot::CATEGORIES.keys.map(&:to_s).index_with do |key|
          { "name" => "Snapshot #{key}", "markdown" => "# Snapshot #{key}\n" }
        end
      }
    end
  end

  setup do
    @token = SecureRandom.hex(5).upcase
    @user = User.create!(email: "sku-diagnosis-#{@token.downcase}@example.com", password: "password123")
    @user.roles << Role.find_by!(code: "super_admin")
    @user.update!(time_zone: "Europe/Moscow")
    @sku = Ec::Sku.create!(sku_code: "DIAG-#{@token}", product_name: "Diagnosis test")
    @daily = Ec::SkuDiagnosisRule.create!(name: "Daily #{@token}", prompt: "Check base data", configuration: { "context_keys" => ["base"], "allowed_event_types" => ["stock_risk", "库存风险"] })
    @weekly = Ec::SkuDiagnosisRule.create!(name: "Weekly #{@token}", prompt: "Check lifecycle", frequency: "weekly", configuration: { "context_keys" => ["lifecycle"] })
    @manual = Ec::SkuDiagnosisRule.create!(name: "Manual #{@token}", prompt: "Check manually", frequency: "manual", configuration: { "context_keys" => [ "base" ] })
    @agent_existed = Agent.exists?(code: "sku_diagnosis")
    @snapshot_fetcher = FakeSnapshotFetcher.new
  end

  teardown do
    Ec::AIDiagnosis.where(sku_id: @sku&.id).destroy_all
    Message.where(conversation: Conversation.where(user_id: @user.id)).delete_all
    Conversation.where(user_id: @user.id).delete_all
    Ec::SkuDiagnosisRule.where(id: [ @daily&.id, @weekly&.id, @manual&.id ]).delete_all
    Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
    Agent.where(code: "sku_diagnosis").delete_all unless @agent_existed
    UserRole.where(user_id: @user&.id).delete_all
    User.where(id: @user&.id).delete_all
  end

  test "runs daily rule with selected context and saves on the scheduled Shanghai date" do
    client = SavingClient.new
    date = Date.new(2026, 9, 15)
    diagnosis_runner(date: date, client: client).run

    assert_equal 2, client.requests.size
    request = client.requests.first
    assert_equal ["save_sku_event"], request.fetch(:tools).map { |tool| tool.fetch(:name) }
    summary = request.fetch(:context).split("已查询到的业务数据摘要：", 2).last
    assert_includes summary, "SKU：#{@sku.sku_code}"
    assert_includes summary, "数据周期：2026-09-07 至 2026-09-13；快照日期：2026-09-15"
    assert_includes summary, "**Snapshot base**\n\n# Snapshot base"
    assert_not_includes summary, '"categories"'
    assert_not_includes summary, "Snapshot lifecycle"
    assert_equal [{ sku_code: @sku.sku_code, snapshot_date: date }], @snapshot_fetcher.calls
    assert_includes request.fetch(:messages).first.fetch(:content), @daily.prompt
    assert_includes request.fetch(:messages).first.fetch(:content), "event_type 建议优先使用以下值，也可按诊断结论填写其他具体类型：stock_risk, 库存风险"

    event = Ec::GeneralDiagnosis.find_by!(sku: @sku).events.sole
    assert_equal @daily.id, event.sub_agent_id
    assert_equal Conversation.where(user: @user).order(:id).last.id, event.conversation_id
    assert_equal ["stock_risk", "Stock issue: sales increased", "Replenish"], [event.event_type, event.message, event.advise]
    assert_equal date, event.created_at.in_time_zone("Asia/Shanghai").to_date
  end

  test "runs weekly rules only on monday" do
    client = SavingClient.new
    diagnosis_runner(date: Date.new(2026, 9, 14), client: client).run

    assert_equal 4, client.requests.size
    assert_equal [@daily.id, @weekly.id].sort, Ec::GeneralDiagnosis.find_by!(sku: @sku).events.pluck(:sub_agent_id).sort
  end

  test "keeps one latest event per SKU and sub-agent across diagnosis dates" do
    diagnosis_runner(date: Date.new(2026, 9, 14), client: SavingClient.new).run
    diagnosis_runner(date: Date.new(2026, 9, 15), client: SavingClient.new).run

    events = Ec::AIDiagnosisEvent
      .joins(:ai_diagnosis)
      .where(ec_ai_diagnosis: { sku_id: @sku.id, type: Ec::GeneralDiagnosis.sti_name })
    daily_events = events.where(sub_agent_id: @daily.id).order(:created_at, :id)
    weekly_events = events.where(sub_agent_id: @weekly.id)

    assert_equal [ false, true ], daily_events.pluck(:is_latest)
    assert weekly_events.sole.is_latest?
  end

  test "runs only manually selected rules regardless of schedule or enabled state" do
    @weekly.update!(enabled: false)
    client = SavingClient.new

    ErpAI::SkuDiagnosisRunner.new(
      as_of_date: Date.new(2026, 9, 15),
      sku_code: @sku.sku_code,
      rule_ids: [ @weekly.id ],
      client: client,
      user: @user,
      snapshot_fetcher: @snapshot_fetcher
    ).run

    assert_equal 2, client.requests.size
    assert_equal [ @weekly.id ], Ec::GeneralDiagnosis.find_by!(sku: @sku).events.pluck(:sub_agent_id)
    summary = client.requests.first.fetch(:context).split("已查询到的业务数据摘要：", 2).last
    assert_includes summary, "**Snapshot lifecycle**\n\n# Snapshot lifecycle"
    assert_not_includes summary, "Snapshot base"
  end

  test "manual frequency runs only when explicitly selected" do
    automatic_client = SavingClient.new
    diagnosis_runner(date: Date.new(2026, 9, 14), client: automatic_client).run

    assert_equal [ @daily.id, @weekly.id ].sort,
      Ec::GeneralDiagnosis.find_by!(sku: @sku).events.pluck(:sub_agent_id).sort

    ErpAI::SkuDiagnosisRunner.new(
      as_of_date: Date.new(2026, 9, 14),
      sku_code: @sku.sku_code,
      rule_ids: [ @manual.id ],
      client: SavingClient.new,
      user: @user,
      snapshot_fetcher: @snapshot_fetcher
    ).run

    assert_equal [ @daily.id, @weekly.id, @manual.id ].sort,
      Ec::GeneralDiagnosis.find_by!(sku: @sku).events.pluck(:sub_agent_id).sort
  end

  test "loads listing content for rules that select it" do
    @daily.update!(configuration: { "context_keys" => [ "listing_content" ] })
    listing_context = Object.new
    listing_context.define_singleton_method(:call) do |sku:|
      "# Active listings for #{sku.sku_code}"
    end
    client = SavingClient.new

    ErpAI::SkuDiagnosisRunner.new(
      as_of_date: Date.new(2026, 9, 15),
      sku_code: @sku.sku_code,
      client: client,
      user: @user,
      snapshot_fetcher: @snapshot_fetcher,
      listing_context: listing_context
    ).run

    summary = client.requests.first.fetch(:context).split("已查询到的业务数据摘要：", 2).last
    assert_includes summary, "**Listing Content**"
    assert_includes summary, "# Active listings for #{@sku.sku_code}"
    assert_not_includes summary, "Snapshot base"
  end

  test "loads product attributes for rules that select them" do
    @daily.update!(configuration: { "context_keys" => [ "product_attributes" ] })
    product_attributes_context = Object.new
    product_attributes_context.define_singleton_method(:call) do |sku:|
      {
        listings: [
          {
            platform: "ozon",
            product_id: "123",
            attributes: [ { id: 85, current_values: [ { value: "Test brand" } ] } ]
          }
        ]
      }
    end
    client = SavingClient.new

    ErpAI::SkuDiagnosisRunner.new(
      as_of_date: Date.new(2026, 9, 15),
      sku_code: @sku.sku_code,
      client: client,
      user: @user,
      snapshot_fetcher: @snapshot_fetcher,
      product_attributes_context: product_attributes_context
    ).run

    summary = client.requests.first.fetch(:context).split("已查询到的业务数据摘要：", 2).last
    assert_includes summary, "**Product Attributes**"
    assert_includes summary, "Test brand"
    assert_not_includes summary, "Snapshot base"
  end

  test "rerunning the same date overwrites the rule event" do
    client = SavingClient.new
    runner = diagnosis_runner(date: Date.new(2026, 9, 15), client: client)
    runner.run
    first_event_id = Ec::GeneralDiagnosis.find_by!(sku: @sku).events.sole.id
    first_conversation_id = Ec::GeneralDiagnosis.find_by!(sku: @sku).events.sole.conversation_id
    runner.run

    event = Ec::GeneralDiagnosis.find_by!(sku: @sku).events.sole
    assert_equal first_event_id, event.id
    assert_not_equal first_conversation_id, event.conversation_id
  end

  test "scoped tool rejects another SKU or rule" do
    executor = ErpAI::SkuDiagnosisRunner::ScopedToolExecutor.new(user: @user, date: Date.new(2026, 9, 15), sku: @sku, rule: @daily)
    result = executor.call(id: "bad", name: "save_sku_event", arguments: {
      sku_code: @sku.sku_code, sub_agent_id: @weekly.id,
      event_type: "stock_risk", severity: "warning", message: "Issue: Evidence", advise: "Action"
    })

    assert_equal "invalid_scope", result.dig(:error, :code)
    assert_not Ec::GeneralDiagnosis.exists?(sku: @sku)
  end

  test "scoped tool accepts an event type outside the rule suggestions" do
    executor = ErpAI::SkuDiagnosisRunner::ScopedToolExecutor.new(user: @user, date: Date.new(2026, 9, 15), sku: @sku, rule: @daily)
    result = executor.call(id: "save", name: "save_sku_event", arguments: {
      sku_code: @sku.sku_code, sub_agent_id: @daily.id,
      event_type: "profit_drop", severity: "warning", message: "Issue: Evidence", advise: "Action"
    })

    assert result.dig(:result, :success)
    event = Ec::GeneralDiagnosis.find_by!(sku: @sku).events.sole
    assert_equal "profit_drop", event.event_type
  end

  test "historical rerun keeps the newer diagnosis latest" do
    client = SavingClient.new
    diagnosis_runner(date: Date.new(2026, 9, 15), client: client).run
    latest = Ec::GeneralDiagnosis.find_by!(sku: @sku, is_latest: true)
    latest_event = latest.events.find_by!(sub_agent_id: @daily.id)

    diagnosis_runner(date: Date.new(2026, 9, 14), client: SavingClient.new).run

    assert_equal latest.id, Ec::GeneralDiagnosis.find_by!(sku: @sku, is_latest: true).id
    assert_equal latest_event.id, Ec::AIDiagnosisEvent.latest.find_by!(sub_agent_id: @daily.id).id
  end

  test "new rules persist all contexts and reject unsupported ones" do
    rule = Ec::SkuDiagnosisRule.new(name: "Default", prompt: "Check")
    assert_equal Ec::SkuDiagnosisRule::CONTEXT_KEYS, rule.configuration.fetch("context_keys")
    rule.allowed_event_types_text = "库存风险（紧急）\n利润 下滑\n库存风险（紧急）"
    assert_equal ["库存风险（紧急）", "利润 下滑"], rule.allowed_event_types
    assert rule.valid?
    rule.context_keys = ["unknown"]
    assert_not rule.valid?
  end

  test "rule accepts event types as entered without localization" do
    @daily.allowed_event_types_text = "库存风险（紧急）\nstock-risk"

    assert @daily.valid?
    assert_equal ["库存风险（紧急）", "stock-risk"], @daily.allowed_event_types
  end

  test "other agents cannot use the event writer" do
    agent = Agent.new(
      code: "other_#{@token.downcase}", name: "Other", system_prompt: "Check",
      model_id: "fake", tools: ["save_sku_event"]
    )
    assert_not agent.valid?
    assert_includes agent.errors.attribute_names, :tools
  end

  private

  def diagnosis_runner(date:, client:)
    ErpAI::SkuDiagnosisRunner.new(
      as_of_date: date,
      sku_code: @sku.sku_code,
      client: client,
      user: @user,
      snapshot_fetcher: @snapshot_fetcher
    )
  end
end
