require "test_helper"

class ImportPendingBatchesFromJsonTest < ActiveSupport::TestCase
  SCRIPT_PATH = Rails.root.join("script/import_pending_batches_from_json.rb")

  setup do
    @token = SecureRandom.hex(4).upcase
    @json_path = Rails.root.join("tmp", "pending_batches_test_#{@token}.json")
  end

  teardown do
    File.delete(@json_path) if File.exist?(@json_path)

    sku_codes = [
      "JSON-SKU-NEW-#{@token}",
      "JSON-SKU-EXISTING-#{@token}",
      "JSON-SKU-CONFLICT-#{@token}"
    ]
    batch_codes = Ec::SkuBatch.where(sku_code: sku_codes).pluck(:batch_code)

    Ec::SkuBatch.where(batch_code: batch_codes).delete_all if batch_codes.any?
    Ec::SkuCost.where(sku_code: sku_codes).delete_all
    Ec::Sku.with_deleted.where(sku_code: sku_codes).delete_all
    Ec::MasterSku.where(master_sku_code: [
      "JSON-MASTER-#{@token}",
      "JSON-OTHER-#{@token}"
    ]).delete_all
  end

  test "imports pending batches json into master sku sku cost and in transit batch records" do
    File.write(@json_path, JSON.pretty_generate([
      {
        sheet_row: 101,
        master_sku_code: "JSON-MASTER-#{@token}",
        sku_code: "JSON-SKU-NEW-#{@token}",
        package_dimensions_cm: {
          raw: "12*8*6cm",
          length_cm: 12,
          width_cm: 8,
          height_cm: 6
        },
        purchase_quantity: 150
      },
      {
        sheet_row: 102,
        master_sku_code: "JSON-MASTER-#{@token}",
        sku_code: "JSON-SKU-EXISTING-#{@token}",
        package_dimensions_cm: {
          raw: "15*10*9cm",
          length_cm: 15,
          width_cm: 10,
          height_cm: 9
        },
        purchase_quantity: 80
      }
    ]))

    master = Ec::MasterSku.create!(
      master_sku_code: "JSON-MASTER-#{@token}",
      product_name: "Existing Master"
    )
    existing_sku = Ec::Sku.create!(
      sku_code: "JSON-SKU-EXISTING-#{@token}",
      product_name: "Existing SKU"
    )

    Object.send(:remove_const, :PendingBatchJsonImport) if Object.const_defined?(:PendingBatchJsonImport)
    load SCRIPT_PATH

    importer = PendingBatchJsonImport.new(json_path: @json_path)

    assert_difference "Ec::SkuBatch.count", 2 do
      assert_difference "Ec::Sku.count", 1 do
        assert_no_difference "Ec::MasterSku.count" do
          assert_difference "Ec::SkuCost.count", 2 do
            importer.call
          end
        end
      end
    end

    new_sku = Ec::Sku.find_by!(sku_code: "JSON-SKU-NEW-#{@token}")
    existing_sku.reload

    assert_equal master, new_sku.master_sku
    assert_equal master, existing_sku.master_sku
    assert_equal true, new_sku.is_active

    new_cost = Ec::SkuCost.find_by!(sku_code: new_sku.sku_code)
    assert_equal BigDecimal("12"), new_cost.pkg_length_cm
    assert_equal BigDecimal("8"), new_cost.pkg_width_cm
    assert_equal BigDecimal("6"), new_cost.pkg_height_cm

    existing_cost = Ec::SkuCost.find_by!(sku_code: existing_sku.sku_code)
    assert_equal BigDecimal("15"), existing_cost.pkg_length_cm
    assert_equal BigDecimal("10"), existing_cost.pkg_width_cm
    assert_equal BigDecimal("9"), existing_cost.pkg_height_cm

    batches = Ec::SkuBatch.where(sku_code: [new_sku.sku_code, existing_sku.sku_code]).order(:sku_code, :id)
    assert_equal 2, batches.size
    assert batches.all? { |batch| batch.status == "in_transit" }
    assert batches.all?(&:normal?)
    assert batches.all? { |batch| batch.received_quantity.zero? }
    assert_equal [80, 150], batches.map(&:purchased_quantity).sort
    assert batches.all? { |batch| batch.batch_code.start_with?("PENDING-") }
  end

  test "raises when sku is already bound to another master sku" do
    File.write(@json_path, JSON.pretty_generate([
      {
        sheet_row: 201,
        master_sku_code: "JSON-MASTER-#{@token}",
        sku_code: "JSON-SKU-CONFLICT-#{@token}",
        package_dimensions_cm: {
          raw: "20*10*5cm",
          length_cm: 20,
          width_cm: 10,
          height_cm: 5
        },
        purchase_quantity: 30
      }
    ]))

    other_master = Ec::MasterSku.create!(master_sku_code: "JSON-OTHER-#{@token}")
    conflict_sku = Ec::Sku.create!(
      sku_code: "JSON-SKU-CONFLICT-#{@token}",
      master_sku: other_master
    )

    Object.send(:remove_const, :PendingBatchJsonImport) if Object.const_defined?(:PendingBatchJsonImport)
    load SCRIPT_PATH

    importer = PendingBatchJsonImport.new(json_path: @json_path)

    error = assert_raises(RuntimeError) { importer.call }
    assert_includes error.message, conflict_sku.sku_code
    assert_equal other_master, conflict_sku.reload.master_sku
    assert_nil Ec::SkuBatch.find_by(sku_code: conflict_sku.sku_code)
  end
end
