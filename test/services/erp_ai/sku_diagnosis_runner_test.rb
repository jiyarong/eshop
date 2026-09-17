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
    assert_includes summary, "**Snapshot base**\n\nDescription base\n\n# Snapshot base"
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
