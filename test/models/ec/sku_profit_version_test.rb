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

  test "Ozon FBS is a supported delivery mode, an unknown one is not" do
    assert build_version.contexts.build(platform: "ozon", market: "ru", delivery_mode: "fbs").valid?

    context = build_version.contexts.build(platform: "ozon", market: "ru", delivery_mode: "rfbs")
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
    identities = ordered.first(Ec::SkuProfitStandardContexts::SCENARIOS.size).map do |context|
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

  test "versions are manual by default and a copy of an automatic version is manual with no data window" do
    assert_equal "manual", build_version.kind

    automatic = build_automatic_version
    assert automatic.save, automatic.errors.full_messages.to_sentence

    copy = automatic.reload.build_copy(effective_from: Date.new(2026, 11, 5), name: "What if 10% cheaper")
    assert copy.manual?
    assert_nil copy.data_from
    assert_nil copy.data_to
    assert copy.save, copy.errors.full_messages.to_sentence
    assert_equal 1, copy.contexts.count
  end

  test "an automatic version is one calendar month, published, never current, with its data window" do
    assert build_automatic_version.valid?

    mid_month = build_automatic_version(effective_from: Date.new(2026, 10, 7))
    assert_not mid_month.valid?
    assert mid_month.errors.of_kind?(:effective_from, :invalid)

    wrong_end = build_automatic_version(effective_to: Date.new(2026, 10, 15))
    assert_not wrong_end.valid?
    assert wrong_end.errors.of_kind?(:effective_to, :invalid)

    no_window = build_automatic_version(data_from: nil, data_to: nil)
    assert_not no_window.valid?
    assert no_window.errors.of_kind?(:data_to, :invalid)

    draft = build_automatic_version(status: "draft")
    assert_not draft.valid?
    assert draft.errors.of_kind?(:status, :invalid)

    current = build_automatic_version(is_current: true)
    assert_not current.valid?
    assert current.errors.of_kind?(:is_current, :invalid)
  end

  test "an automatic version cannot be edited, have its scenarios edited, deleted or made current" do
    version = build_automatic_version
    assert version.save
    version = Ec::SkuProfitVersion.find(version.id)

    version.name = "renamed"
    assert_not version.save
    assert version.errors.of_kind?(:base, :automatic_read_only)

    context = Ec::SkuProfitVersionContext.find_by!(sku_profit_version_id: version.id)
    context.commission_base_price_rub = 999
    assert_not context.save
    assert context.errors.of_kind?(:base, :automatic_read_only)

    assert_not context.destroy
    assert_not Ec::SkuProfitVersion.find(version.id).destroy
    assert_raises(ActiveRecord::RecordInvalid) { version.make_current! }
    assert Ec::SkuProfitVersion.exists?(version.id)
    assert Ec::SkuProfitVersionContext.exists?(context.id)
  end

  test "the owner of an automatic version can replace it with system_write" do
    version = build_automatic_version
    assert version.save
    version = Ec::SkuProfitVersion.find(version.id)

    version.system_write = true
    assert version.destroy
    assert_not Ec::SkuProfitVersion.exists?(version.id)
    assert_equal 0, Ec::SkuProfitVersionContext.where(sku_profit_version_id: version.id).count
  end

  test "the kind of a saved version never changes" do
    version = build_version
    version.contexts.build(platform: "wb", market: "ru", delivery_mode: "fbo")
    assert version.save

    version.kind = "automatic"
    assert_not version.valid?
    assert version.errors.of_kind?(:kind, :invalid)
  end

  test "one automatic version per SKU and month, and months do not clash with published manual versions" do
    assert build_automatic_version.save

    assert_raises(ActiveRecord::RecordNotUnique) { build_automatic_version.save(validate: false) }

    manual = build_version(status: "published", effective_from: Date.new(2026, 10, 1), effective_to: Date.new(2026, 10, 31))
    manual.contexts.build(platform: "wb", market: "ru", delivery_mode: "fbo")
    assert manual.save, manual.errors.full_messages.to_sentence

    next_month = build_automatic_version(effective_from: Date.new(2026, 11, 1), effective_to: Date.new(2026, 11, 30))
    assert next_month.save
  end

  test "the database refuses a current automatic version" do
    version = build_automatic_version
    assert version.save

    assert_raises(ActiveRecord::StatementInvalid) do
      Ec::SkuProfitVersion.where(id: version.id).update_all(is_current: true)
    end
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

  def build_automatic_version(effective_from: Date.new(2026, 10, 1), effective_to: nil, status: "published", is_current: false,
    data_from: Date.new(2026, 9, 1), data_to: Date.new(2026, 9, 28))
    version = @sku.profit_versions.new(
      name: "Automatic #{effective_from}",
      kind: "automatic",
      status: status,
      is_current: is_current,
      effective_from: effective_from,
      effective_to: effective_to || effective_from.end_of_month,
      data_from: data_from,
      data_to: data_to
    )
    version.contexts.build(platform: "wb", market: "ru", delivery_mode: "fbo")
    version
  end
end
