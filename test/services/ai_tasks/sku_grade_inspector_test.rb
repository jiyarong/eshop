require "test_helper"

class AITasks::SkuGradeInspectorTest < ActiveSupport::TestCase
  class FakeClient
    attr_reader :requests

    def initialize(&on_complete)
      @requests = []
      @on_complete = on_complete
    end

    def complete(request)
      @requests << request
      @on_complete&.call(request)
      { content: "Grade 检查工具流程已完成。" }
    end
  end

  setup do
    @token = SecureRandom.hex(5).upcase
    @as_of_date = Date.new(2026, 8, 4)
    @user = User.create!(
      email: "grade-inspector-#{@token.downcase}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
    @sku = Ec::Sku.create!(
      sku_code: "GRADE-#{@token}",
      product_name: "Grade inspector",
      is_active: true
    )
    @client = FakeClient.new { persist_grade_result }
    @agent_existed = Agent.exists?(code: AITasks::SkuGradeInspector::AGENT_CODE)
    @original_profit_query_run = Ec::WeeklySummaryDeepQuery.method(:run)
    Ec::WeeklySummaryDeepQuery.define_singleton_method(:run) do |from_date:, to_date:, sku_codes:|
      { rows: sku_codes.map { |sku_code| { sku: sku_code } } }
    end
    @weekly_rate_existed = Ec::WeeklyRate.exists?(week_start: last_week_start)
    Ec::WeeklyRate.find_or_create_by!(week_start: last_week_start) do |rate|
      rate.rate_cny_rub = 10
      rate.rate_byn_rub = 3
    end
  end

  teardown do
    Ec::GradeInspect.where(sku_id: @sku&.id).destroy_all
    Message.where(conversation: Conversation.where(user: @user)).delete_all
    Conversation.where(user: @user).delete_all
    Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
    Agent.where(code: AITasks::SkuGradeInspector::AGENT_CODE).delete_all unless @agent_existed
    Ec::WeeklySummaryDeepQuery.define_singleton_method(:run, @original_profit_query_run)
    Ec::WeeklyRate.where(week_start: last_week_start).delete_all unless @weekly_rate_existed
    User.where(id: @user&.id).delete_all
  end

  test "runs the attached prompt with ERP request access and no assembled data" do
    conversation = AITasks::SkuGradeInspector.run(
      as_of_date: @as_of_date,
      sku_code: @sku.sku_code,
      client: @client,
      user: @user
    ).sole

    assert_equal "sku_grade_inspections", conversation.module_name
    assert_equal @sku.id.to_s, conversation.business_object_id
    assert_equal({ "from" => "2026-06-08", "to" => "2026-08-02" }, conversation.time_range)
    assert_equal [ "user", "assistant" ], conversation.messages.order(:created_at, :id).pluck(:role)

    question = conversation.messages.order(:created_at, :id).first.content
    assert_includes question, @sku.sku_code
    assert_includes question, "2026-06-08"
    assert_includes question, "2026-08-02"
    assert_includes question, "/ai/skus/inventory_availability"
    assert_includes question, "/ai/diagnosis_results"
    assert_not_includes conversation.context.to_h, "data_summary"

    request = @client.requests.sole
    assert_equal Agent::SKU_GRADE_INSPECTOR_PROMPT, request.fetch(:system_prompt)
    assert_includes request.fetch(:system_prompt), "GET /ai/diagnosis_results?type=GradeInspect"
    assert_equal [ "erp_ai_request" ], request.fetch(:tools).map { |tool| tool.fetch(:name) }
    assert_includes request.fetch(:context), "已查询到的业务数据摘要：未提供"
    assert_equal conversation, Ec::GradeInspect.find_by!(sku: @sku).events.sole.conversation
  end

  test "retries once when the model finishes without persisting diagnosis events" do
    attempts = 0
    client = FakeClient.new do
      attempts += 1
      persist_grade_result if attempts == 2
    end

    conversation = AITasks::SkuGradeInspector.run(
      as_of_date: @as_of_date,
      sku_code: @sku.sku_code,
      client: client,
      user: @user
    ).sole

    assert_equal 2, client.requests.size
    assert_equal 2, Conversation.where(user: @user, module_name: "sku_grade_inspections").count
    assert_includes conversation.messages.order(:id).first.content, "必须实际调用写回接口"
    diagnosis = Ec::GradeInspect.find_by!(sku: @sku)
    assert_equal 1, diagnosis.events.count
    assert_equal conversation, diagnosis.events.sole.conversation
  end

  test "skips a SKU already inspected for the same completed-week cutoff" do
    diagnosis = Ec::GradeInspect.create!(
      sku: @sku,
      submitted_by: @user,
      analyzed_at: Time.current,
      data: { analysis_cutoff_date: "2026-08-02" }
    )
    diagnosis.events.create!(
      event_type: "grade_stable",
      severity: "info",
      scope: "grade",
      message: "维持当前 Grade。",
      details: {},
      position: 0
    )

    result = AITasks::SkuGradeInspector.run(
      as_of_date: @as_of_date + 1.day,
      sku_code: @sku.sku_code,
      client: @client,
      user: @user
    )

    assert_empty result
    assert_empty @client.requests
  end

  test "skips a SKU without last week's profit data" do
    query_calls = []
    original_profit_query_run = Ec::WeeklySummaryDeepQuery.method(:run)
    Ec::WeeklySummaryDeepQuery.define_singleton_method(:run) do |from_date:, to_date:, sku_codes:|
      query_calls << { from_date: from_date, to_date: to_date, sku_codes: sku_codes }
      { rows: [] }
    end

    result = AITasks::SkuGradeInspector.run(
      as_of_date: @as_of_date,
      sku_code: @sku.sku_code,
      client: @client,
      user: @user
    )

    assert_empty result
    assert_empty @client.requests
    assert_equal [ {
      from_date: Date.new(2026, 7, 27),
      to_date: Date.new(2026, 8, 2),
      sku_codes: [ @sku.sku_code ]
    } ], query_calls
  ensure
    Ec::WeeklySummaryDeepQuery.define_singleton_method(:run, original_profit_query_run)
  end

  private

  def last_week_start
    @as_of_date.beginning_of_week(:monday) - 1.week
  end

  def persist_grade_result
    diagnosis = Ec::GradeInspect.find_or_create_by!(
      sku: @sku,
      data: { analysis_cutoff_date: "2026-08-02" }
    ) do |record|
      record.submitted_by = @user
      record.analyzed_at = Time.current
    end
    return if diagnosis.events.exists?

    diagnosis.events.create!(
      event_type: "grade_stable",
      severity: "info",
      scope: "grade",
      message: "维持当前 Grade。",
      details: {},
      position: 0
    )
  end
end
