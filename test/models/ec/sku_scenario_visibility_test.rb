require "test_helper"

class Ec::SkuScenarioVisibilityTest < ActiveSupport::TestCase
  setup do
    @sku = Ec::Sku.create!(sku_code: "VIS-#{SecureRandom.hex(4).upcase}")
    @identity = { "platform" => "wb", "market" => "ru", "delivery_mode" => "fbo", "company_type" => "small" }
  end

  teardown do
    ids = Ec::SkuScenarioVisibility.where(sku_id: @sku.id).pluck(:id)
    Ec::OperationLog.where(record_type: "Ec::SkuScenarioVisibility", record_id: ids).delete_all
    Ec::SkuScenarioVisibility.where(id: ids).delete_all
    Ec::OperationLog.where(record_type: "Ec::Sku", record_id: @sku.id).delete_all
    Ec::Sku.with_deleted.where(id: @sku.id).delete_all
  end

  test "a scenario nobody touched is shown" do
    assert_empty Ec::SkuScenarioVisibility.hidden_keys_for(@sku)
  end

  test "hiding and restoring flips one row per scenario" do
    Ec::SkuScenarioVisibility.set!(sku: @sku, identity: @identity, hidden: true)
    assert_equal Set["wb|ru|fbo|main|small"], Ec::SkuScenarioVisibility.hidden_keys_for(@sku)

    Ec::SkuScenarioVisibility.set!(sku: @sku, identity: @identity, hidden: false)
    assert_empty Ec::SkuScenarioVisibility.hidden_keys_for(@sku)
    assert_equal 1, Ec::SkuScenarioVisibility.where(sku_id: @sku.id).count
  end

  test "the warehouse region defaults to main and case does not matter" do
    record = Ec::SkuScenarioVisibility.set!(sku: @sku, identity: @identity.transform_values(&:upcase), hidden: true)

    assert_equal "main", record.warehouse_region
    assert_equal "wb|ru|fbo|main|small", Ec::SkuScenarioVisibility.key_for(record)
  end

  test "only the standard scenarios can be stored" do
    assert_raises(ActiveRecord::RecordInvalid) do
      Ec::SkuScenarioVisibility.set!(sku: @sku, identity: @identity.merge("market" => "kz"), hidden: true)
    end
    assert_raises(ActiveRecord::RecordInvalid) do
      Ec::SkuScenarioVisibility.set!(sku: @sku, identity: @identity.except("company_type"), hidden: true)
    end
  end

  test "another SKU's choice does not leak" do
    other = Ec::Sku.create!(sku_code: "VIS-#{SecureRandom.hex(4).upcase}")
    Ec::SkuScenarioVisibility.set!(sku: other, identity: @identity, hidden: true)

    assert_empty Ec::SkuScenarioVisibility.hidden_keys_for(@sku)
  ensure
    Ec::OperationLog.where(record_type: "Ec::SkuScenarioVisibility", record_id: Ec::SkuScenarioVisibility.where(sku_id: other.id).pluck(:id)).delete_all
    Ec::SkuScenarioVisibility.where(sku_id: other.id).delete_all
    Ec::OperationLog.where(record_type: "Ec::Sku", record_id: other.id).delete_all
    Ec::Sku.with_deleted.where(id: other.id).delete_all
  end

  test "each change is written to the operation log" do
    Current.user = nil
    record = Ec::SkuScenarioVisibility.set!(sku: @sku, identity: @identity, hidden: true)
    Ec::SkuScenarioVisibility.set!(sku: @sku, identity: @identity, hidden: false)

    logs = Ec::OperationLog.where(record_type: "Ec::SkuScenarioVisibility", record_id: record.id).order(:id)
    assert_equal %w[create update], logs.map(&:action)
    assert_equal "hidden", logs.last.changeset.first.fetch("field")
  end
end
