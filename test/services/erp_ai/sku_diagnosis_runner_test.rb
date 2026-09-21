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
      advice = question.include?("运营执行的建议操作")
      tool_call = if advice
        { id: "create-#{requests.size}", name: "create_sku_advise", arguments: {
          sku_code: sku_code, severity: "critical", event_type: "补充库存",
          message: "销量增长且库存偏低；运营在本周补充库存，补货后观察缺货率。"
        } }
      else
        { id: "save-#{requests.size}", name: "save_sku_event", arguments: {
          sku_code: sku_code, sub_agent_id: question[/当前子规则 ID：(\d+)/, 1].to_i, severity: "warning",
          event_type: "stock_risk", message: "Stock issue: sales increased"
        } }
      end
      { content: nil, tool_calls: [tool_call] }
    end
  end

  class MultipleAdviceClient
    def initialize(fail_after_tools: false)
      @fail_after_tools = fail_after_tools
      @request_count = 0
    end

    def complete(request)
      @request_count += 1
      raise "Advice generation failed" if @fail_after_tools && @request_count > 1
      return { content: "Saved", tool_calls: [] } if @request_count > 1

      question = request.fetch(:messages).first.fetch(:content)
      sku_code = question[/当前 SKU：([^\n]+)/, 1]
      {
        content: nil,
        tool_calls: [
          {
            id: "create-stock",
            name: "create_sku_advise",
            arguments: {
              sku_code: sku_code,
              severity: "critical",
              event_type: "补充库存",
              message: "库存不足，需要补充库存。"
            }
          },
          {
            id: "create-listing",
            name: "create_sku_advise",
            arguments: {
              sku_code: sku_code,
              severity: "critical",
              event_type: "优化主图",
              message: "转化偏低，需要优化主图。"
            }
          }
        ]
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
          {
            "name" => "Snapshot #{key}",
            "description" => "Description #{key}",
            "markdown" => "# Snapshot #{key}\n"
          }
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
    @additional_rules = []
    @agent_existed = Agent.exists?(code: "sku_diagnosis")
    @snapshot_fetcher = FakeSnapshotFetcher.new
  end

  teardown do
    Ec::AIDiagnosis.where(sku_id: @sku&.id).destroy_all
    Message.where(conversation: Conversation.where(user_id: @user.id)).delete_all
    Conversation.where(user_id: @user.id).delete_all
    Ec::SkuDiagnosisRule.where(id: @additional_rules&.map(&:id)).delete_all
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
    assert_includes summary, "**Snapshot base**\n\nDescription base\n\n# Snapshot base"
    assert_not_includes summary, '"categories"'
    assert_not_includes summary, "Snapshot lifecycle"
    assert_equal [{ sku_code: @sku.sku_code, snapshot_date: date }], @snapshot_fetcher.calls
    assert_includes request.fetch(:messages).first.fetch(:content), @daily.prompt
    assert_includes request.fetch(:messages).first.fetch(:content), "event_type 建议优先使用以下值，也可按诊断结论填写其他具体类型：stock_risk, 库存风险"

    event = Ec::GeneralDiagnosis.find_by!(sku: @sku).events.sole
    assert_equal @daily.id, event.sub_agent_id
    assert_equal Conversation.where(user: @user).order(:id).last.id, event.conversation_id
    assert_equal ["stock_risk", "Stock issue: sales increased"], [event.event_type, event.message]
    assert_nil event.advise
    assert_not_includes request.fetch(:messages).first.fetch(:content), "advise"
    assert_equal date, event.created_at.in_time_zone("Asia/Shanghai").to_date
  end

  test "batch diagnosis only runs for SKUs present in the previous weekly profit report" do
    report_sku = @sku
    no_report_sku = Ec::Sku.create!(sku_code: "NO-REPORT-#{@token}", product_name: "No report")
    original_run = Ec::WeeklySummaryDeepQuery.method(:run)
    report_query_args = nil
    Ec::WeeklySummaryDeepQuery.define_singleton_method(:run) do |from_date:, to_date:, sku_codes:, include_comparison:|
      report_query_args = { from_date: from_date, to_date: to_date, sku_codes: sku_codes, include_comparison: include_comparison }
      { rows: [ { sku: report_sku.sku_code } ] }
    end

    client = SavingClient.new
    ErpAI::SkuDiagnosisRunner.new(
      as_of_date: Date.new(2026, 9, 15),
      client: client,
      user: @user,
      snapshot_fetcher: @snapshot_fetcher
    ).run

    assert Ec::GeneralDiagnosis.exists?(sku: report_sku)
    assert_not Ec::GeneralDiagnosis.exists?(sku: no_report_sku)
    assert_equal [ report_sku.sku_code ], @snapshot_fetcher.calls.map { |call| call.fetch(:sku_code) }
    assert_equal(
      { from_date: Date.new(2026, 9, 7), to_date: Date.new(2026, 9, 13), sku_codes: [], include_comparison: false },
      report_query_args
    )
  ensure
    Ec::AIDiagnosis.where(sku_id: no_report_sku&.id).destroy_all
    no_report_sku&.destroy!
    Ec::WeeklySummaryDeepQuery.define_singleton_method(:run, original_run) if original_run
  end

  test "uses the canonical context description when an older snapshot has none" do
    snapshot = @snapshot_fetcher.fetch(@sku.sku_code, snapshot_date: Date.new(2026, 9, 15))
    snapshot.fetch("categories").fetch("base").delete("description")
    runner = diagnosis_runner(date: Date.new(2026, 9, 15), client: SavingClient.new)

    section = runner.send(:context_section, "base", snapshot)

    assert_includes section, Ec::SkuContextSnapshot.context_descriptions.fetch(:base)
    assert_includes section, "# Snapshot base"
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
    assert_includes summary, "**Snapshot lifecycle**\n\nDescription lifecycle\n\n# Snapshot lifecycle"
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

  test "scheduled runs apply execution conditions while manual runs ignore them" do
    @daily.update!(configuration: {
      "context_keys" => ["base"],
      "execution_conditions" => { "grade" => ["A"], "stage" => ["grw"] }
    })
    @sku.marketing_states.create!(grade: "B", stage: "new", effective_at: Time.current)

    scheduled_client = SavingClient.new
    diagnosis_runner(date: Date.new(2026, 9, 15), client: scheduled_client).run
    assert_empty scheduled_client.requests
    assert_not Ec::GeneralDiagnosis.exists?(sku: @sku)

    manual_client = SavingClient.new
    ErpAI::SkuDiagnosisRunner.new(
      as_of_date: Date.new(2026, 9, 15),
      sku_code: @sku.sku_code,
      rule_ids: [@daily.id],
      client: manual_client,
      user: @user,
      snapshot_fetcher: @snapshot_fetcher
    ).run

    assert_equal 2, manual_client.requests.size
    assert_equal [@daily.id], Ec::GeneralDiagnosis.find_by!(sku: @sku).events.pluck(:sub_agent_id)
  end

  test "loads listing content for rules that select it" do
    @daily.update!(configuration: { "context_keys" => [ "ozon_listing_content" ] })
    stores = 3.times.map do |index|
      Ec::Store.create!(
        platform: "ozon",
        store_name: "Listing #{index + 1} #{@token}",
        company_type: "small",
        is_active: true
      )
    end
    expected_sku_products = stores.each_with_index.map do |store, index|
      Ec::SkuProduct.create!(
        sku: @sku,
        store: store,
        platform: "ozon",
        product_id: "LISTING-#{index + 1}-#{@token}",
        is_active: true
      )
    end
    image_blobs_by_product = expected_sku_products.to_h do |sku_product|
      blobs = %w[main merged].map do |kind|
        ActiveStorage::Blob.create_and_upload!(
          io: StringIO.new("#{sku_product.product_id}-#{kind}-image"),
          filename: "#{sku_product.product_id}-#{kind}.jpg",
          content_type: "image/jpeg"
        )
      end
      [ sku_product.id, blobs ]
    end
    image_blobs = expected_sku_products.flat_map { |sku_product| image_blobs_by_product.fetch(sku_product.id) }
    listing_context = Object.new
    received_attributes = nil
    received_listing_platforms = nil
    received_attribute_platforms = nil
    listing_context.define_singleton_method(:description) do
      "**Listing Context Data Description**\n\n- `name`: platform listing name."
    end
    listing_context.define_singleton_method(:call) do |sku:, product_attributes:, platforms:|
      received_attributes = product_attributes
      received_listing_platforms = platforms
      "# Ozon Listing Context\n\n## Active listings for #{sku.sku_code}"
    end
    product_attributes_context = Object.new
    product_attributes_context.define_singleton_method(:call) do |sku:, platforms:|
      received_attribute_platforms = platforms
      { listings: [ { sku_product_id: expected_sku_products.first.id, marker: "attributes for #{sku.sku_code}" } ] }
    end
    listing_context.define_singleton_method(:image_attachments) do |sku_product:|
      file = Struct.new(:blob) do
        def attached? = true
      end
      image_blobs_by_product.fetch(sku_product.id).map { |blob| Struct.new(:file).new(file.new(blob)) }
    end
    client = SavingClient.new

    ErpAI::SkuDiagnosisRunner.new(
      as_of_date: Date.new(2026, 9, 15),
      sku_code: @sku.sku_code,
      client: client,
      user: @user,
      snapshot_fetcher: @snapshot_fetcher,
      listing_context: listing_context,
      product_attributes_context: product_attributes_context
    ).run

    summary = client.requests.first.fetch(:context).split("已查询到的业务数据摘要：", 2).last
    assert_includes summary, "**Listing Context Data Description**"
    assert_includes summary, "- `name`: platform listing name."
    assert_includes summary, "# Ozon Listing Context"
    assert_includes summary, "## Active listings for #{@sku.sku_code}"
    assert_equal 1, summary.scan("# Ozon Listing Context").size
    assert_equal "attributes for #{@sku.sku_code}", received_attributes.dig(:listings, 0, :marker)
    assert_equal [ "ozon" ], received_listing_platforms
    assert_equal [ "ozon" ], received_attribute_platforms
    assert_not_includes summary, "Snapshot base"
    assert_includes client.requests.first.fetch(:messages).first.fetch(:content).first.fetch(:text),
      "每个 Listing product 的图片均按两张一组排列"
    image_parts = client.requests.first.fetch(:messages).first.fetch(:content).select do |part|
      part.fetch(:type) == "image_url"
    end
    assert_equal 6, image_parts.size
    user_message = Conversation.where(user: @user).order(:id).last.messages.find_by!(role: "user")
    assert_equal image_blobs.map(&:id), user_message.images.blobs.pluck(:id)
  ensure
    user_message&.images&.detach
    image_blobs&.each(&:purge)
    expected_sku_products&.each(&:destroy!)
    stores&.each(&:destroy!)
  end

  test "loads the combined listing context for legacy product attributes rules" do
    @daily.update!(configuration: { "context_keys" => [ "product_attributes" ] })
    received_platforms = nil
    product_attributes_context = Object.new
    product_attributes_context.define_singleton_method(:call) do |sku:, platforms:|
      received_platforms = platforms
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
    listing_context = Object.new
    listing_context.define_singleton_method(:description) { "**Listing Context Data Description**" }
    listing_context.define_singleton_method(:call) do |sku:, product_attributes:, platforms:|
      listing = product_attributes.fetch(:listings).sole
      raise "platform mismatch" unless platforms == %w[ozon wb]

      "# Ozon Listing Context\n\n## #{sku.sku_code}\n\n- attributes: #{listing.dig(:attributes, 0, :current_values, 0, :value)}"
    end
    listing_context.define_singleton_method(:image_attachments) { |sku_product:| [] }
    client = SavingClient.new

    ErpAI::SkuDiagnosisRunner.new(
      as_of_date: Date.new(2026, 9, 15),
      sku_code: @sku.sku_code,
      client: client,
      user: @user,
      snapshot_fetcher: @snapshot_fetcher,
      product_attributes_context: product_attributes_context,
      listing_context: listing_context
    ).run

    summary = client.requests.first.fetch(:context).split("已查询到的业务数据摘要：", 2).last
    assert_includes summary, "# Ozon Listing Context"
    assert_includes summary, "Test brand"
    assert_not_includes summary, "**Product Attributes**"
    assert_not_includes summary, "Snapshot base"
    assert_equal %w[ozon wb], received_platforms
    assert_equal %w[ozon_listing_content wb_listing_content], @daily.reload.context_keys
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

  test "does not create operational advice when summary is requested" do
    client = SavingClient.new
    extra_rules = create_additional_rules(4)
    rule_ids = [ @daily, @weekly, *extra_rules ].map(&:id)
    travel_to Time.zone.local(2026, 9, 15, 12) do
      diagnosis_runner(date: Date.new(2026, 9, 15), client: client, summary: true, rule_ids: rule_ids).run
    end

    assert_operator client.requests.size, :>=, rule_ids.size
    assert_empty client.requests.select { |request| request.fetch(:tools).map { |tool| tool.fetch(:name) } == [ "create_sku_advise" ] }

    events = Ec::GeneralDiagnosis.find_by!(sku: @sku).events.order(:id)
    assert_equal rule_ids.sort, events.filter_map(&:sub_agent_id).sort
    assert_not events.any? { |event| event.scope == "advise" }
  end

  test "does not refresh advice when summary is requested" do
    date = Date.new(2026, 9, 15)
    zone = Time.find_zone!(ErpAI::SkuDiagnosisRunner::TIME_ZONE)
    previous_diagnosis = Ec::GeneralDiagnosis.create!(
      sku: @sku, submitted_by: @user, created_at: zone.local(2026, 9, 14, 3)
    )
    previous_advice = previous_diagnosis.events.create!(
      event_type: "历史建议", severity: "critical", scope: "advise", message: "Previous", is_latest: true
    )
    daily_diagnosis = Ec::GeneralDiagnosis.create!(
      sku: @sku, submitted_by: @user, created_at: zone.local(2026, 9, 15, 3)
    )
    stale_daily_advice = daily_diagnosis.events.create!(
      event_type: "当日旧建议", severity: "critical", scope: "advise", message: "Stale", is_latest: true
    )

    diagnosis_runner(
      date: date, client: MultipleAdviceClient.new, summary: true, force: true, rule_ids: []
    ).run

    assert previous_advice.reload.is_latest?
    assert Ec::AIDiagnosisEvent.exists?(stale_daily_advice.id)
    refreshed = daily_diagnosis.events.where(scope: "advise").order(:id)
    assert_equal [ "当日旧建议" ], refreshed.pluck(:event_type)
    assert_equal [ true ], refreshed.pluck(:is_latest)
  end

  test "restores advice events when the joint diagnosis fails after creating advice" do
    date = Date.new(2026, 9, 15)
    zone = Time.find_zone!(ErpAI::SkuDiagnosisRunner::TIME_ZONE)
    previous_diagnosis = Ec::GeneralDiagnosis.create!(
      sku: @sku, submitted_by: @user, created_at: zone.local(2026, 9, 14, 3)
    )
    previous_advice = previous_diagnosis.events.create!(
      event_type: "历史建议", severity: "critical", scope: "advise", message: "Previous", is_latest: true
    )
    daily_diagnosis = Ec::GeneralDiagnosis.create!(
      sku: @sku, submitted_by: @user, created_at: zone.local(2026, 9, 15, 3)
    )
    daily_advice = daily_diagnosis.events.create!(
      event_type: "当日旧建议", severity: "critical", scope: "advise", message: "Current", is_latest: true
    )

    diagnosis_runner(
      date: date,
      client: MultipleAdviceClient.new(fail_after_tools: true),
      summary: true,
      force: true,
      rule_ids: []
    ).run

    assert previous_advice.reload.is_latest?
    assert daily_advice.reload.is_latest?
    assert_equal [ "当日旧建议" ], daily_diagnosis.events.where(scope: "advise").pluck(:event_type)
  end

  test "selects at most one event per rule in each of the four recent weeks" do
    diagnosis_ids = []
    week_starts = 3.downto(0).map { |weeks_ago| Date.new(2026, 9, 14) - weeks_ago.weeks }
    week_starts.each_with_index do |week_start, index|
      diagnosis = Ec::GeneralDiagnosis.create!(sku: @sku, submitted_by: @user, data: {}, created_at: week_start.to_time + 3.hours)
      diagnosis_ids << diagnosis.id
      diagnosis.events.create!(
        sub_agent_id: @daily.id,
        event_type: "daily_#{index}",
        severity: "warning",
        message: "daily #{index}",
        advise: "follow #{index}",
        created_at: week_start.to_time + 4.hours
      )
    end
    duplicate_week = week_starts.last
    diagnosis = Ec::GeneralDiagnosis.find(diagnosis_ids.last)
    newest = diagnosis.events.create!(
      sub_agent_id: @daily.id,
      event_type: "daily_newest",
      severity: "critical",
      message: "newest event",
      advise: "follow newest",
      created_at: duplicate_week.to_time + 5.hours
    )

    runner = diagnosis_runner(date: Date.new(2026, 9, 15), client: SavingClient.new)
    events = runner.send(:summary_events_for, @sku)

    assert_equal 4, events.size
    assert_equal [ "daily_0", "daily_1", "daily_2", "daily_newest" ], events.map(&:event_type)
    assert_equal newest.id, events.last.id
  end

  test "skips the joint diagnosis when fewer than six latest sub-rule events exist" do
    client = SavingClient.new
    extra_rules = create_additional_rules(3)
    rule_ids = [ @daily, @weekly, *extra_rules ].map(&:id)
    travel_to Time.zone.local(2026, 9, 15, 12) do
      diagnosis_runner(date: Date.new(2026, 9, 15), client: client, summary: true, rule_ids: rule_ids).run
    end

    events = Ec::GeneralDiagnosis.find_by!(sku: @sku).events
    assert_equal 5, events.where(is_latest: true).count
    assert_not events.where(sub_agent_id: nil).exists?
  end

  test "skips the joint diagnosis when the latest sub-rule event is older than thirty hours" do
    client = SavingClient.new
    extra_rules = create_additional_rules(4)
    rule_ids = [ @daily, @weekly, *extra_rules ].map(&:id)
    travel_to Time.zone.local(2026, 9, 16, 12) do
      diagnosis_runner(date: Date.new(2026, 9, 15), client: client, summary: true, rule_ids: rule_ids).run
    end

    events = Ec::GeneralDiagnosis.find_by!(sku: @sku).events
    assert_equal 6, events.where(is_latest: true).count
    assert_not events.where(sub_agent_id: nil).exists?
  end

  test "skips the joint diagnosis without sub-rules" do
    client = SavingClient.new
    ErpAI::SkuDiagnosisRunner.new(
      as_of_date: Date.new(2026, 9, 15),
      sku_code: @sku.sku_code,
      rule_ids: [],
      summary: true,
      client: client,
      user: @user,
      snapshot_fetcher: @snapshot_fetcher
    ).run

    assert_not Ec::GeneralDiagnosis.exists?(sku: @sku)
    assert_empty client.requests
  end

  test "does not force-run joint advice without sub-rule events" do
    client = SavingClient.new
    diagnosis_runner(
      date: Date.new(2026, 9, 15), client: client, summary: true, force: true, rule_ids: []
    ).run

    assert_empty client.requests
    assert_not Ec::GeneralDiagnosis.exists?(sku: @sku)
  end

  test "scoped tool rejects another SKU or rule" do
    executor = ErpAI::SkuDiagnosisRunner::ScopedToolExecutor.new(user: @user, date: Date.new(2026, 9, 15), sku: @sku, rule: @daily)
    result = executor.call(id: "bad", name: "save_sku_event", arguments: {
      sku_code: @sku.sku_code, sub_agent_id: @weekly.id,
      event_type: "stock_risk", severity: "warning", message: "Issue: Evidence"
    })

    assert_equal "invalid_scope", result.dig(:error, :code)
    assert_not Ec::GeneralDiagnosis.exists?(sku: @sku)
  end

  test "scoped joint tool rejects event updates" do
    executor = ErpAI::SkuDiagnosisRunner::ScopedToolExecutor.new(
      user: @user, date: Date.new(2026, 9, 15), sku: @sku, allowed_tools: [ "create_sku_advise" ]
    )
    result = executor.call(id: "update", name: "update_sku_diagnosis_event", arguments: {
      sku_code: @sku.sku_code, event_id: 1, severity: "critical"
    })

    assert_equal "invalid_scope", result.dig(:error, :code)
  end

  test "scoped tool accepts an event type outside the rule suggestions" do
    executor = ErpAI::SkuDiagnosisRunner::ScopedToolExecutor.new(user: @user, date: Date.new(2026, 9, 15), sku: @sku, rule: @daily)
    result = executor.call(id: "save", name: "save_sku_event", arguments: {
      sku_code: @sku.sku_code, sub_agent_id: @daily.id,
      event_type: "profit_drop", severity: "warning", message: "Issue: Evidence"
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

  test "normalizes and validates execution conditions" do
    rule = Ec::SkuDiagnosisRule.new(name: "Conditions", prompt: "Check")
    rule.execution_conditions = { grade: ["a", "A"], stage: ["GRW"] }

    assert_equal({ "grade" => ["A"], "stage" => ["grw"] }, rule.execution_conditions)
    assert rule.valid?

    rule.execution_conditions = { grade: ["D"], stage: ["old"] }
    assert_not rule.valid?
    assert_includes rule.errors[:configuration].join, "unsupported grade values"
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

  def diagnosis_runner(date:, client:, summary: false, force: false, rule_ids: nil)
    ErpAI::SkuDiagnosisRunner.new(
      as_of_date: date,
      sku_code: @sku.sku_code,
      rule_ids: rule_ids,
      summary: summary,
      force: force,
      client: client,
      user: @user,
      snapshot_fetcher: @snapshot_fetcher
    )
  end

  def create_additional_rules(count)
    count.times.map do |index|
      rule = Ec::SkuDiagnosisRule.create!(name: "Additional #{index} #{@token}", prompt: "Check additional data")
      @additional_rules << rule
      rule
    end
  end
end
