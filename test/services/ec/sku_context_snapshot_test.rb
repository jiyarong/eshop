require "test_helper"

class Ec::SkuContextSnapshotTest < ActiveSupport::TestCase
  class FakeContextBuilder
    class << self
      attr_accessor :arguments
    end

    def initialize(**arguments)
      self.class.arguments = arguments
    end

    def call
      sku = self.class.arguments.fetch(:sku)
      period_from = self.class.arguments.fetch(:period_from)
      period_to = self.class.arguments.fetch(:period_to)
      today = self.class.arguments.fetch(:today)
      time_zone = self.class.arguments.fetch(:time_zone)

      {
        data: {
          schema_version: 3,
          sku_code: sku.sku_code,
          period: {
            from: period_from.iso8601,
            to: period_to.iso8601,
            as_of: today.iso8601,
            time_zone: time_zone.name,
            week_starts_on: "monday"
          }
        }.merge(
          Ec::SkuContextSnapshot::CATEGORIES.keys.index_with { |key| { value: key.to_s } }
        )
      }
    end
  end

  class FakeMarkdownRenderer
    def self.call(payload)
      section_key = payload.fetch(:data).keys.last
      "# #{section_key}\n"
    end
  end

  setup do
    @sku = Ec::Sku.create!(
      sku_code: "SKU-CONTEXT-SNAPSHOT-#{SecureRandom.hex(6)}",
      product_name: "SKU context snapshot test"
    )
    @snapshot_date = Date.new(2026, 9, 15)
  end

  teardown do
    Ec::Snapshot.where(snapshot_type: Ec::SkuContextSnapshot.snapshot_type, sku_id: @sku&.id).delete_all
    Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
    FakeContextBuilder.arguments = nil
  end

  test "captures raw JSON and markdown for every context category" do
    rows = Ec::SkuContextSnapshot.new(
      snapshot_date: @snapshot_date,
      sku_scope: Ec::Sku.where(id: @sku.id),
      context_builder: FakeContextBuilder,
      markdown_renderer: FakeMarkdownRenderer
    ).capture

    assert_equal 1, rows.size
    content = rows.sole.fetch(:content)
    assert_equal @sku.id, rows.sole.fetch(:sku_id)
    assert_equal 3, content.fetch(:schema_version)
    assert_equal @sku.sku_code, content.fetch(:sku_code)
    assert_equal(
      {
        from: "2026-09-07",
        to: "2026-09-13",
        as_of: "2026-09-15",
        time_zone: "Asia/Shanghai",
        week_starts_on: "monday"
      },
      content.fetch(:period)
    )

    categories = content.fetch(:categories)
    assert_equal Ec::SkuContextSnapshot::CATEGORIES.keys, categories.keys
    Ec::SkuContextSnapshot::CATEGORIES.each do |section_key, category_name|
      category = categories.fetch(section_key)
      assert_equal category_name, category.fetch(:name)
      assert category.fetch(:description).present?
      assert_includes category.fetch(:description), "| 字段 | 中文含义 | 说明 |"
      assert_equal [ :schema_version, :sku_code, :period, section_key ], category.dig(:raw_json, :data).keys
      assert_equal({ value: section_key.to_s }, category.dig(:raw_json, :data, section_key))
      assert_equal "# #{section_key}\n", category.fetch(:markdown)
    end

    orders_description = categories.dig(:ec_orders_full_period, :description)
    assert_includes orders_description, "`buyer_paid_unit_price`"
    assert_not_includes orders_description, "`order_key`"
    assert_not_includes orders_description, "`buyer_paid_synced_at`"
  end

  test "is registered with ten-day retention" do
    assert_includes Ec::SnapshotRunner::SNAPSHOT_MODULES, Ec::SkuContextSnapshot
    assert_equal 10, Ec::SkuContextSnapshot.retention_days
  end

  test "captures one requested SKU" do
    test_case = self
    sku_id = @sku.id
    sku_code = @sku.sku_code
    expected_snapshot_date = @snapshot_date
    replacement = ->(snapshot_date:, sku_scope:) {
      test_case.assert_equal expected_snapshot_date, snapshot_date
      test_case.assert_equal [ sku_id ], sku_scope.pluck(:id)
      Object.new.tap do |snapshot|
        snapshot.define_singleton_method(:capture) { [ { sku_id: sku_id, content: { sku_code: sku_code } } ] }
      end
    }
    row = with_singleton_method(Ec::SkuContextSnapshot, :new, replacement) do
      Ec::SkuContextSnapshot.capture_for(sku: @sku, snapshot_date: @snapshot_date)
    end

    assert_equal @sku.id, row.fetch(:sku_id)
    assert_equal @sku.sku_code, row.dig(:content, :sku_code)
  end

  private

  def with_singleton_method(klass, method_name, replacement)
    original = klass.method(method_name)
    klass.define_singleton_method(method_name, replacement)
    yield
  ensure
    klass.define_singleton_method(method_name, original)
  end
end
