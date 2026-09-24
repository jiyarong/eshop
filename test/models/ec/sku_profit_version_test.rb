require "test_helper"

class Ec::SkuProfitVersionTest < ActiveSupport::TestCase
  setup do
    @sku = Ec::Sku.create!(
      sku_code: "PROFIT-#{SecureRandom.hex(5).upcase}",
      product_name: "Profit version test",
      is_active: true
    )
  end

  teardown do
    version_ids = Ec::SkuProfitVersion.where(sku_id: @sku&.id).pluck(:id)
    context_ids = Ec::SkuProfitVersionContext.where(sku_profit_version_id: version_ids).pluck(:id)
    Ec::OperationLog.where(record_type: "Ec::SkuProfitVersionContext", record_id: context_ids).delete_all
    Ec::OperationLog.where(record_type: "Ec::SkuProfitVersion", record_id: version_ids).delete_all
    Ec::SkuProfitVersionContext.where(id: context_ids).delete_all
    Ec::SkuProfitVersion.where(id: version_ids).delete_all
    Ec::OperationLog.where(record_type: "Ec::Sku", record_id: @sku&.id).delete_all
    Ec::Sku.where(id: @sku&.id).delete_all
  end

  test "one version owns any number of normalized contexts" do
    version = build_version
    version.contexts.build(platform: "WB", market: "RU", delivery_mode: "FBO", warehouse_region: "MAIN", company_type: "GENERAL")
    version.contexts.build(platform: "WB", market: "RU", delivery_mode: "FBS", warehouse_region: "REGION", company_type: "SMALL")

    assert version.save
    assert_equal 2, version.contexts.count
    assert_equal %w[fbo fbs], version.contexts.order(:delivery_mode).pluck(:delivery_mode)
    assert_equal %w[ru], version.contexts.distinct.pluck(:market)
  end

  test "context business combination is unique within a version including null dimensions" do
    version = build_version
    version.contexts.build(platform: "wb", market: "ru", delivery_mode: "fbo")
    assert version.save

    duplicate = version.contexts.build(platform: "WB", market: "RU", delivery_mode: "FBO")

    assert_not duplicate.valid?
    assert duplicate.errors.added?(:platform, :taken, value: "wb")
  end

  test "Ozon FBS remains unsupported" do
    context = build_version.contexts.build(platform: "ozon", market: "ru", delivery_mode: "fbs")

    assert_not context.valid?
    assert context.errors.of_kind?(:delivery_mode, :inclusion)
  end

  test "Ozon contexts normalize an omitted company type to general" do
    version = build_version
    context = version.contexts.build(platform: "OZON", market: "RU", delivery_mode: "FBO")

    assert version.save
    assert_equal "general", context.company_type
    assert_equal context, version.context_for(platform: "ozon", market: "ru", delivery_mode: "fbo")
  end

  test "context rejects unsupported company types but permits an incomplete draft" do
    version = build_version
    incomplete = version.contexts.build(platform: "wb", market: "ru", delivery_mode: "fbo")
    unsupported = version.contexts.build(platform: "wb", market: "ru", delivery_mode: "fbs", company_type: "vat_20")

    assert incomplete.valid?
    assert_not unsupported.valid?
    assert unsupported.errors.of_kind?(:company_type, :inclusion)
  end

  test "published versions require contexts and cannot overlap" do
    empty_version = build_version(status: "published")
    assert_not empty_version.valid?
    assert empty_version.errors.of_kind?(:contexts, :blank)

    first = build_version(status: "published", effective_from: Date.new(2026, 1, 1), effective_to: Date.new(2026, 1, 31))
    first.contexts.build(platform: "wb", market: "ru", delivery_mode: "fbo")
    assert first.save

    overlapping = build_version(status: "published", effective_from: Date.new(2026, 1, 31), effective_to: Date.new(2026, 2, 28))
    overlapping.contexts.build(platform: "wb", market: "ru", delivery_mode: "fbo")
    assert_not overlapping.valid?
    assert overlapping.errors.of_kind?(:effective_from, :taken)
  end

  test "draft versions may overlap and for_date returns only the published version" do
    published = build_version(status: "published", effective_from: Date.new(2026, 3, 1), effective_to: Date.new(2026, 3, 31))
    published.contexts.build(platform: "wb", market: "ru", delivery_mode: "fbo")
    published.save!
    draft = build_version(status: "draft", effective_from: Date.new(2026, 3, 15), effective_to: Date.new(2026, 4, 15))
    draft.save!

    assert_equal published, @sku.profit_versions.for_date(Date.new(2026, 3, 20)).sole
    assert draft.persisted?
  end

  test "context stores calculation inputs in typed columns" do
    context = build_version.contexts.build(platform: "wb", market: "ru", delivery_mode: "fbo")
    context.assign_input_values(commission_rate: "0.175", return_rate: "0.18")

    assert context.valid?
    assert_equal 0.175.to_d, context.commission_rate
    assert_equal 0.18.to_d, context.return_rate
    assert_equal({ "commission_rate" => 0.175.to_d, "return_rate" => 0.18.to_d }, context.calculation_inputs.slice("commission_rate", "return_rate"))
  end

  test "build_copy duplicates all contexts into a new draft" do
    original = build_version(status: "published")
    context = original.contexts.build(platform: "wb", market: "ru", delivery_mode: "fbo")
    context.assign_input_values(commission_rate: "0.175")
    original.save!

    copy = original.build_copy(effective_from: Date.new(2027, 1, 1), name: "Copied")

    assert copy.new_record?
    assert_equal "draft", copy.status
    assert_equal "Copied", copy.name
    assert_equal 1, copy.contexts.size
    assert_equal original.contexts.first.calculation_inputs, copy.contexts.first.calculation_inputs
    assert_equal "pending", copy.contexts.first.calculation_status
  end

  test "standard contexts keep the same order regardless of insertion order" do
    version = build_version
    Ec::SkuProfitStandardContexts::SCENARIOS.reverse_each { |attributes| version.contexts.build(attributes) }
    extra = version.contexts.build(
      platform: "wb", market: "ru", delivery_mode: "fbo", warehouse_region: "regional", company_type: "general"
    )

    ordered = Ec::SkuProfitStandardContexts.sort(version.contexts)
    identities = ordered.first(6).map do |context|
      context.attributes.slice(*Ec::SkuProfitStandardContexts::IDENTITY_KEYS)
    end

    assert_equal Ec::SkuProfitStandardContexts::SCENARIOS, identities
    assert_equal extra, ordered.last
  end

  test "lock_version rejects stale writes" do
    version = build_version
    version.save!
    stale = Ec::SkuProfitVersion.find(version.id)
    version.update!(note: "first writer")

    assert_raises(ActiveRecord::StaleObjectError) { stale.update!(note: "stale writer") }
  end

  private

  def build_version(status: "draft", effective_from: Date.new(2026, 1, 1), effective_to: nil)
    @sku.profit_versions.new(
      name: "Version #{SecureRandom.hex(3)}",
      status: status,
      effective_from: effective_from,
      effective_to: effective_to
    )
  end
end
