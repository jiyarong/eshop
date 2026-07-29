require "test_helper"

class AITasks::SkuInventoryHealthCheckJobTest < ActiveJob::TestCase
  setup do
    @token = SecureRandom.hex(6)
    @user = User.create!(
      email: "inventory-health-job-#{@token}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
    @checked_sku = create_sku("CHECKED")
    @stale_sku = create_sku("STALE")
    @no_turnover_sku = create_sku("NO-TURNOVER")
  end

  teardown do
    sku_ids = [ @checked_sku, @stale_sku, @no_turnover_sku ].compact.map(&:id)
    Ec::RestockingDiagnosis.where(sku_id: sku_ids).destroy_all
    Ec::Sku.where(id: sku_ids).delete_all
    User.where(id: @user&.id).delete_all
  end

  test "runs only skus with turnover days and no result today" do
    shanghai = Time.find_zone!("Asia/Shanghai")

    travel_to shanghai.local(2026, 7, 28, 21, 30) do
      create_result(@checked_sku, created_at: Time.current)
      create_result(@stale_sku, created_at: 1.day.ago)
      metrics = {
        @checked_sku.sku_code => { turnover_days: BigDecimal("10") },
        @stale_sku.sku_code => { turnover_days: BigDecimal("20") },
        @no_turnover_sku.sku_code => { turnover_days: nil }
      }
      calls = []

      with_stubbed_metrics(metrics) do
        with_stubbed_singleton_method(AITasks::SkuInventoryHealthCheck, :run, ->(sku_code:) { calls << sku_code }) do
          AITasks::SkuInventoryHealthCheckJob.perform_now
        end
      end

      assert_equal [ @stale_sku.sku_code ], calls
    end
  end

  test "logs a failed check and continues with the remaining skus" do
    metrics = {
      @checked_sku.sku_code => { turnover_days: BigDecimal("10") },
      @stale_sku.sku_code => { turnover_days: BigDecimal("20") }
    }
    calls = []
    log_messages = []
    failed_sku_code = @checked_sku.sku_code
    run_check = lambda do |sku_code:|
      calls << sku_code
      raise RuntimeError, "AI unavailable" if sku_code == failed_sku_code
    end

    logger = Object.new
    logger.define_singleton_method(:error) { |message| log_messages << message }

    with_stubbed_metrics(metrics) do
      with_stubbed_singleton_method(AITasks::SkuInventoryHealthCheck, :run, run_check) do
        with_stubbed_singleton_method(Rails, :logger, -> { logger }) do
          AITasks::SkuInventoryHealthCheckJob.perform_now
        end
      end
    end

    assert_equal [ @checked_sku.sku_code, @stale_sku.sku_code ], calls
    assert_includes log_messages, "[AITasks::SkuInventoryHealthCheck] RuntimeError: AI unavailable"
  end

  private

  def create_sku(prefix)
    Ec::Sku.create!(
      sku_code: "#{prefix}-#{@token}",
      product_name: "Inventory health job test",
      is_active: true
    )
  end

  def create_result(sku, created_at:)
    Ec::RestockingDiagnosis.create!(
      sku: sku,
      submitted_by: @user,
      analyzed_at: created_at,
      created_at: created_at,
      updated_at: created_at
    )
  end

  def with_stubbed_metrics(metrics, &block)
    query = Object.new
    query.define_singleton_method(:call) { metrics }

    with_stubbed_singleton_method(
      Ec::InventoryTurnoverMetricsQuery,
      :new,
      ->(*) { query },
      &block
    )
  end

  def with_stubbed_singleton_method(object, method_name, replacement)
    original_method = object.method(method_name)
    object.define_singleton_method(method_name, replacement)
    yield
  ensure
    object.define_singleton_method(method_name, original_method)
  end
end
