require "test_helper"

class Ec::PalletPlans::OzonSupplyRunnerTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  self.use_transactional_tests = true

  class FakeClient
    attr_reader :calls
    attr_accessor :responses

    def initialize(responses)
      @responses, @calls = responses, []
    end

    %i[create_draft draft_info timeslots create_supply supply_status bundle_items create_cargoes cargoes_info cargoes_rules].each do |method|
      define_method(method) do |*args, **kwargs|
        @calls << [method, args, kwargs]
        response = @responses.fetch(method)
        response = response.call(*args, **kwargs) if response.respond_to?(:call)
        raise response if response.is_a?(Exception)
        response.deep_dup
      end
    end
  end

  setup do
    @token = SecureRandom.hex(6).upcase
    @user = User.create!(email: "supply-runner-#{@token}@example.com", password: "password123")
    @user.roles << Role.find_by!(code: "manager")
    @account = RawOzon::SellerAccount.create!(client_id: "supply-#{@token}", api_key: "test", company_type: "general")
    @store = Ec::Store.create!(platform: "ozon", store_name: "Supply #{@token}", company_type: "general", ozon_raw_account_id: @account.id)
    @sku = Ec::Sku.create!(sku_code: "SUPPLY-RUNNER-#{@token}")
    Ec::SkuOperatorAssignment.create!(sku: @sku, user: @user)
    @product = Ec::SkuProduct.create!(sku: @sku, store: @store, product_id: "10001", platform_sku_id: "1001")
    @plan = Ec::PalletPlan.create!(store: @store, created_by: @user, macrolocal_cluster_id: 761, cluster_name: "Москва",
      status: "draft", from_date: Date.new(2026, 10, 1), to_date: Date.new(2026, 10, 19), target_days: 28, time_zone: "Asia/Shanghai")
    @item = @plan.items.create!(sku_code: @sku.sku_code, sku_product: @product, platform_sku_id: "1001", boxes: 2, pcs: 10, units: 20)
    @pallet = @plan.pallets.create!(position: 1, layout: { weight: 100 }, metrics: { height: 120, gross_weight: 125, boxes: 2, units: 20 })
    @pallet.items.create!(pallet_plan_item: @item, boxes: 2, units: 20, layout: {})
    Ec::SkuBatch.create!(sku: @sku, batch_code: "SUPPLY-#{@token}", status: "received", purchased_quantity: 100, received_quantity: 100, purchase_unit_price_cny: 1)
    @submission = @plan.create_ozon_supply_submission!(request_key: SecureRandom.uuid, data: { "supply_type" => "DIRECT" })
    @warehouse = { "availability_status" => { "state" => "FULL_AVAILABLE" }, "bundle_id" => "draft-bundle",
      "storage_warehouse" => { "warehouse_id" => 9001, "name" => "Москва" } }
    @slot = { "from_in_timezone" => "2026-10-22T10:00:00", "to_in_timezone" => "2026-10-22T11:00:00" }
    @bundle = [{ "sku" => 1001, "quantity" => 20, "barcode" => "4601234567890", "offer_id" => "OFFER-1001", "quant" => 2 }]
    @client = FakeClient.new(
      create_draft: { "draft_id" => 123 },
      draft_info: { "status" => "SUCCESS", "clusters" => [{ "macrolocal_cluster_id" => 761, "supply_type" => "DIRECT", "warehouses" => [@warehouse] }] },
      timeslots: { "result" => { "drop_off_warehouse_timeslots" => { "warehouse_timezone" => "Europe/Moscow", "days" => [{ "timeslots" => [@slot] }] } } },
      bundle_items: @bundle,
      create_supply: { "draft_id" => 123 },
      supply_status: { "status" => "SUCCESS", "order_id" => 456 },
      create_cargoes: { "operation_id" => "cargo-op", "errors" => { "error_reasons" => [], "items_validation" => [] } },
      cargoes_info: { "status" => "SUCCESS", "result" => { "cargoes" => [{ "key" => "#{@plan.plan_no}-1", "value" => { "cargo_id" => 789 } }] } },
      cargoes_rules: { "supply_check_lists" => [{ "supply_id" => 2000064845539,
        "cargoes_presents_rule" => { "satisfied" => true }, "is_valid_distribution_rule" => { "is_applicable" => true, "satisfied" => true } }] }
    )
    @sync_calls = []
    test = self
    @sync = Object.new
    @sync.define_singleton_method(:sync_supply_orders) { |order_ids:| test.send(:import_order, order_ids) }
  end

  test "creates a supply then writes pallets using actual platform quantum and fills back IDs" do
    run_step
    assert_equal "calculating", @submission.reload.state
    assert_equal "123", @submission.draft_id
    assert_equal({ sku: 1001, quantity: 20 }, @client.calls.first.last.fetch(:items).sole)
    run_step
    assert_equal "warehouse_required", @submission.reload.state
    actions.select_warehouse!(9001)
    run_step
    assert_equal "timeslot_required", @submission.reload.state
    assert_equal "Europe/Moscow", @submission.data["warehouse_timezone"]
    actions.submit!("0")
    assert_equal "reserved", @plan.reload.status
    7.times { run_step }

    assert_equal "completed", @submission.reload.state, @submission.last_error
    assert_equal "456", @plan.reload.ozon_order_id
    assert_equal "ORDER-456", @plan.supply_order_number
    assert_equal "READY_TO_SUPPLY", @plan.platform_status
    assert_equal "reserved", @plan.status
    assert_equal "2000064845539", @pallet.reload.ozon_supply_id
    assert_equal "789", @pallet.ozon_cargo_id
    cargo_call = @client.calls.find { |call| call.first == :create_cargoes }.last
    assert_equal "PALLET", cargo_call.fetch(:cargoes).sole.dig(:value, :type)
    assert_equal({ barcode: "4601234567890", offer_id: "OFFER-1001", quant: 2, quantity: 20 }, cargo_call.fetch(:cargoes).sole.dig(:value, :items).sole)
    assert_equal 2, @sync_calls.size
    2.times { run_step }
    assert_equal 1, @client.calls.count { |call| call.first == :create_supply }
    assert_equal 1, @client.calls.count { |call| call.first == :create_cargoes }
  end

  test "box cargoes conserve quantities and fill platform IDs through the complete workflow" do
    @pallet.update!(cargo_type: "box", metrics: { gross_weight: 10 })
    @pallet.items.sole.update!(boxes: 1, units: 10)
    second = @plan.pallets.create!(position: 2, cargo_type: "box", metrics: { gross_weight: 10 })
    second.items.create!(pallet_plan_item: @item, boxes: 1, units: 10)
    @client.responses[:cargoes_info]["result"]["cargoes"] << { "key" => "#{@plan.plan_no}-2", "value" => { "cargo_id" => 790 } }
    ready_to_submit
    7.times { run_step }
    assert_equal "completed", @submission.reload.state, @submission.last_error
    cargoes = @client.calls.find { |call| call.first == :create_cargoes }.last.fetch(:cargoes)
    assert_equal %w[BOX BOX], cargoes.map { |cargo| cargo.dig(:value, :type) }
    assert_equal [10, 10], cargoes.map { |cargo| cargo.dig(:value, :items).sole[:quantity] }
    assert_equal ["789", "790"], @plan.pallets.reload.map(&:ozon_cargo_id)
    assert_equal [2, 2], cargoes.map { |cargo| cargo.dig(:value, :items).sole[:quant] }
  end

  test "mixed cargoes submit both pallets and loose boxes with conserved quantities" do
    @pallet.items.sole.update!(boxes: 1, units: 10)
    box = @plan.pallets.create!(position: 2, cargo_type: "box", metrics: { gross_weight: 10 })
    box.items.create!(pallet_plan_item: @item, boxes: 1, units: 10)
    @client.responses[:cargoes_info]["result"]["cargoes"] << { "key" => "#{@plan.plan_no}-2", "value" => { "cargo_id" => 790 } }

    ready_to_submit
    7.times { run_step }

    assert_equal "completed", @submission.reload.state, @submission.last_error
    cargoes = @client.calls.find { |call| call.first == :create_cargoes }.last.fetch(:cargoes)
    assert_equal %w[PALLET BOX], cargoes.map { |cargo| cargo.dig(:value, :type) }
    assert_equal [10, 10], cargoes.map { |cargo| cargo.dig(:value, :items).sole[:quantity] }
    assert_equal ["789", "790"], @plan.pallets.reload.map(&:ozon_cargo_id)
  end

  test "authorizes the submitting user when a workbench plan has a different creator" do
    creator = User.create!(email: "supply-creator-#{@token}@example.com", password: "password123")
    @plan.update!(created_by: creator)
    @submission.update!(data: @submission.data.merge("requested_by_id" => @user.id))

    run_step

    assert_equal "calculating", @submission.reload.state
    assert_equal 1, @client.calls.count { |call| call.first == :create_draft }
  end

  test "rechecks the submitting user's permission before writing to Ozon" do
    requester = User.create!(email: "supply-requester-#{@token}@example.com", password: "password123")
    @submission.update!(data: @submission.data.merge("requested_by_id" => requester.id))

    run_step

    assert_equal "failed", @submission.reload.state
    assert_empty @client.calls
  end

  test "lost supply creation response resumes by draft without repeating the write" do
    ready_to_submit
    @client.responses[:create_supply] = Timeout::Error.new("lost response")
    run_step
    assert_equal "creating", @submission.reload.state
    run_step
    assert_equal "syncing", @submission.reload.state
    assert_equal "456", @submission.order_id
    assert_equal 1, @client.calls.count { |call| call.first == :create_supply }
  end

  test "a definitively failed creation allows selecting a new slot on the same draft" do
    ready_to_submit
    run_step
    @client.responses[:supply_status] = { "status" => "FAILED", "error_reasons" => ["TIMESLOT_NOT_AVAILABLE"] }
    run_step
    assert_equal "failed", @submission.reload.state
    assert @submission.warehouse_selectable?
    assert @submission.cancellable?
    assert_nil @submission.order_id
    actions.select_warehouse!(9001)
    assert_equal "loading_timeslots", @submission.reload.state
    assert_not @submission.data["order_attempted"]
    assert_equal "123", @submission.draft_id
    assert_equal 1, @client.calls.count { |call| call.first == :create_supply }
  end

  test "a failed result containing an order ID requires review rather than a new order" do
    ready_to_submit
    run_step
    @client.responses[:supply_status] = { "status" => "FAILED", "order_id" => 456 }
    run_step
    assert_equal "review_required", @submission.reload.state
    assert_equal "456", @submission.order_id
    assert_not @submission.warehouse_selectable?
    assert_not @submission.cancellable?
  end

  test "rejects a reduced platform bundle before creating an order" do
    ready_to_submit
    @client.responses[:bundle_items].sole["quantity"] = 18
    run_step
    assert_equal "failed", @submission.reload.state
    assert_empty @client.calls.select { |call| call.first == :create_supply }
    assert_nil @submission.order_id
  end

  test "rejects missing platform metadata before creating an order" do
    ready_to_submit
    @client.responses[:bundle_items].sole.delete("quant")
    run_step
    assert_equal "failed", @submission.reload.state
    assert_includes @submission.last_error, @sku.sku_code
    assert_empty @client.calls.select { |call| call.first == :create_supply }
  end

  test "ignores partial warehouses and a different cluster" do
    run_step
    @client.responses[:draft_info]["clusters"].first["warehouses"].first["availability_status"]["state"] = "PARTIAL_AVAILABLE"
    run_step
    assert_equal "failed", @submission.reload.state
    assert_nil @submission.order_id
  end

  test "unknown cargo write outcome stops for review and cannot be retried" do
    ready_to_submit
    3.times { run_step }
    assert_equal "cargoes", @submission.reload.state
    @client.responses[:create_cargoes] = EOFError.new("lost response")
    run_step
    assert_equal "review_required", @submission.reload.state
    assert_not @submission.retryable?
    2.times { run_step }
    assert_equal 1, @client.calls.count { |call| call.first == :create_cargoes }
  end

  test "a crash after starting a write is not allowed to repeat that write" do
    @submission.update!(state: "draft_submitting")
    run_step
    assert_equal "review_required", @submission.reload.state
    assert_empty @client.calls

    @submission.update!(state: "order_submitting", draft_id: "123")
    run_step
    assert_equal "creating", @submission.reload.state
    assert_empty @client.calls
    run_step
    assert_equal "syncing", @submission.reload.state
  end

  test "pending results exhaust bounded polls then only retry reading" do
    @submission.update!(state: "creating", draft_id: "123", poll_attempts: 59)
    @client.responses[:supply_status] = { "status" => "IN_PROGRESS" }
    run_step
    assert_equal "failed", @submission.reload.state
    assert @submission.retryable?
    actions.retry!
    assert_equal "creating", @submission.reload.state
    assert_equal 0, @submission.poll_attempts
    assert_empty @client.calls.select { |call| call.first == :create_supply }
  end

  test "platform rule failure retains created IDs and never reports completion" do
    ready_to_submit
    6.times { run_step }
    assert_equal "finalizing", @submission.reload.state
    @client.responses[:cargoes_rules]["supply_check_lists"].sole["is_valid_distribution_rule"]["satisfied"] = false
    run_step
    assert_equal "failed", @submission.reload.state
    assert_equal "456", @submission.order_id
    assert_equal "789", @pallet.reload.ozon_cargo_id
    assert @submission.retryable?
  end

  test "reconciliation refuses a changed destination before writing cargoes" do
    ready_to_submit
    2.times { run_step }
    import_order(["456"])
    RawOzon::SupplyOrderItem.where(supply_order_id: RawOzon::SupplyOrder.where(account_id: @account.id).select(:id)).update_all(storage_warehouse_id: 9002)
    @sync.define_singleton_method(:sync_supply_orders) { |order_ids:| }
    run_step
    assert_equal "failed", @submission.reload.state
    assert_empty @client.calls.select { |call| call.first == :create_cargoes }
  end

  test "selection is limited to returned warehouses and slots and expires after thirty minutes" do
    @submission.update!(state: "warehouse_required", draft_id: "123", data: @submission.data.merge("warehouses" => [@warehouse], "draft_created_at" => Time.current.iso8601))
    assert_raises(Ec::PalletPlans::Error) { actions.select_warehouse!(9999) }
    actions.select_warehouse!(9001)
    run_step
    assert_raises(Ec::PalletPlans::Error) { actions.submit!("-1") }
    assert_raises(Ec::PalletPlans::Error) { actions.submit!("100") }
    @submission.update!(data: @submission.data.merge("draft_created_at" => 31.minutes.ago.iso8601))
    error = assert_raises(Ec::PalletPlans::Error) { actions.submit!("0") }
    assert_equal :draft_expired, error.key
    assert_equal "draft", @plan.reload.status
  end

  test "stock is rechecked when confirming and an unsubmitted draft can be cancelled" do
    ready_to_submit(confirm: false)
    Ec::SkuBatch.where(sku_code: @sku.sku_code).update_all(received_quantity: 0)
    assert_raises(Ec::PalletPlans::Error) { actions.submit!("0") }
    assert_equal "timeslot_required", @submission.reload.state
    actions.cancel!
    assert_equal "cancelled", @submission.reload.state
    run_step
    assert_empty @client.calls.select { |call| call.first == :create_supply }
  end

  test "multiple pallets conserve units and receive distinct platform cargo IDs" do
    @pallet.items.sole.update!(boxes: 1, units: 10)
    second = @plan.pallets.create!(position: 2, layout: { weight: 100 }, metrics: { height: 120, gross_weight: 125, boxes: 1, units: 10 })
    second.items.create!(pallet_plan_item: @item, boxes: 1, units: 10, layout: {})
    @client.responses[:cargoes_info]["result"]["cargoes"] << { "key" => "#{@plan.plan_no}-2", "value" => { "cargo_id" => 790 } }
    ready_to_submit
    7.times { run_step }
    assert_equal "completed", @submission.reload.state, @submission.last_error
    cargoes = @client.calls.find { |call| call.first == :create_cargoes }.last.fetch(:cargoes)
    assert_equal [10, 10], cargoes.map { |cargo| cargo.dig(:value, :items).sole[:quantity] }
    assert_equal ["789", "790"], @plan.pallets.reload.map(&:ozon_cargo_id)
  end

  test "revoked SKU access stops a queued external write" do
    Ec::SkuOperatorAssignment.where(sku_code: @sku.sku_code).delete_all
    run_step
    assert_equal "failed", @submission.reload.state
    assert_empty @client.calls
  end

  test "a warehouse with no slots can be changed without creating an order" do
    2.times { run_step }
    actions.select_warehouse!(9001)
    @client.responses[:timeslots] = { "result" => { "drop_off_warehouse_timeslots" => { "days" => [] } } }
    run_step
    assert_equal "failed", @submission.reload.state
    actions.select_warehouse!(9001)
    assert_equal "loading_timeslots", @submission.reload.state
    assert_empty @client.calls.select { |call| call.first == :create_supply }
  end

  test "recovery enqueues stale running submissions without writing to the platform" do
    @submission.update!(state: "creating", updated_at: 2.minutes.ago)
    assert_enqueued_with(job: Ec::OzonSupplySubmissionJob, args: [@submission.id]) do
      Ec::OzonSupplySubmissionJob.perform_now
    end
    assert_empty @client.calls
    @submission.update!(state: "warehouse_required")
    assert_no_enqueued_jobs { Ec::OzonSupplySubmissionJob.perform_now }
  end

  private

  def run_step
    Ec::PalletPlans::OzonSupplyRunner.new(submission: @submission.reload, client: @client, sync: @sync).call
  end

  def actions
    Ec::PalletPlans::OzonSupplyActions.new(submission: @submission.reload)
  end

  def ready_to_submit(confirm: true)
    2.times { run_step }
    actions.select_warehouse!(9001)
    run_step
    actions.submit!("0") if confirm
  end

  def import_order(order_ids)
    @sync_calls << order_ids
    order = RawOzon::SupplyOrder.find_or_create_by!(account: @account, supply_order_id: "456") do |record|
      record.status = "READY_TO_SUPPLY"
      record.raw_json = { "order_number" => "ORDER-456" }
      record.synced_at = Time.current
    end
    return if order.supply_order_items.exists?
    order.supply_order_items.create!(bundle_id: "order-bundle", ozon_supply_id: 2000064845539, platform_sku_id: 1001,
      quantity: 20, state: "READY_TO_SUPPLY", macrolocal_cluster_id: 761, storage_warehouse_id: 9001,
      raw_json: @bundle.sole, synced_at: Time.current)
  end
end
