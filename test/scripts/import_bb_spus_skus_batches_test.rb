require "test_helper"

class ImportBbSpusSkusBatchesTest < ActiveSupport::TestCase
  SCRIPT_PATH = Rails.root.join("script/import_bb_spus_skus_batches.rb")

  setup do
    load SCRIPT_PATH
    @token = SecureRandom.hex(4).upcase
    @developer = User.create!(email: "bb-developer-#{@token}@example.com", password: "password", name: BbSpuSkuBatchImport::DEVELOPER_NAME)
    @other_developer = User.create!(email: "bb-other-#{@token}@example.com", password: "password", name: "Other #{@token}")
    @supplier = Ec::Supplier.create!(name: BbSpuSkuBatchImport::SUPPLIER_NAME)
    @row = {
      source_row: 902,
      master_sku_code: "BB-SPU-#{@token}",
      sku_code: "BB-SKU-#{@token}",
      purchase_unit_price_cny: 27,
      purchased_quantity: 200,
      inner_size: "37*36*8cm",
      inner_box_weight_kg: 0.35,
      outer_size: "58*38*50cm",
      outer_box_weight_kg: 10.35,
      outer_box_pcs: 25
    }
  end

  teardown do
    sku_code = @row[:sku_code]
    Ec::SkuBatch.where(sku_code: sku_code).delete_all
    Ec::SkuDimension.where(sku_code: sku_code).delete_all
    Ec::SkuDeveloperAssignment.where(sku_code: sku_code).delete_all
    Ec::Sku.with_deleted.where(sku_code: sku_code).delete_all
    Ec::MasterSku.where(master_sku_code: @row[:master_sku_code]).delete_all
    Ec::Company.where(id: @supplier&.id).delete_all
    User.where(id: [@developer&.id, @other_developer&.id]).delete_all
    Object.send(:remove_const, :BbSpuSkuBatchImport) if Object.const_defined?(:BbSpuSkuBatchImport)
  end

  test "imports SPU SKU developer dimensions and ordered batch idempotently" do
    existing_sku = Ec::Sku.create!(sku_code: @row[:sku_code])
    Ec::SkuDeveloperAssignment.create!(sku: existing_sku, user: @other_developer)
    importer = BbSpuSkuBatchImport.new(rows: [@row], env: { "APPLY" => "1" }, stdout: StringIO.new)

    assert_difference "Ec::MasterSku.count", 1 do
      assert_no_difference "Ec::Sku.count" do
        assert_difference "Ec::SkuDimension.count", 1 do
          assert_difference "Ec::SkuBatch.count", 1 do
            importer.call
          end
        end
      end
    end
    assert_no_difference ["Ec::MasterSku.count", "Ec::Sku.count", "Ec::SkuDimension.count", "Ec::SkuBatch.count"] do
      importer.call
    end

    sku = Ec::Sku.find_by!(sku_code: @row[:sku_code])
    assert_equal @row[:master_sku_code], sku.master_sku.master_sku_code
    assert_equal [@developer.id], sku.developer_assignments.pluck(:user_id)

    dimensions = Ec::SkuDimension.find_by!(sku_code: sku.sku_code)
    assert_equal BigDecimal("37"), dimensions.inner_length_cm
    assert_equal BigDecimal("36"), dimensions.inner_width_cm
    assert_equal BigDecimal("8"), dimensions.inner_height_cm
    assert_equal BigDecimal("0.35"), dimensions.inner_box_weight_kg
    assert_equal BigDecimal("58"), dimensions.outer_length_cm
    assert_equal BigDecimal("38"), dimensions.outer_width_cm
    assert_equal BigDecimal("50"), dimensions.outer_height_cm
    assert_equal BigDecimal("10.35"), dimensions.outer_box_weight_kg
    assert_equal 25, dimensions.outer_box_pcs

    batch = Ec::SkuBatch.find_by!(sku_code: sku.sku_code)
    assert_equal "ordered", batch.status
    assert_equal @supplier.id, batch.supplier_id
    assert_equal 200, batch.purchased_quantity
    assert_equal 0, batch.received_quantity
    assert_equal BigDecimal("27"), batch.purchase_unit_price_cny
    assert_equal Date.new(2026, 9, 28), batch.expected_arrival_on
  end

  test "dry run rolls back all changes" do
    importer = BbSpuSkuBatchImport.new(rows: [@row], env: {}, stdout: StringIO.new)

    assert_no_difference ["Ec::MasterSku.count", "Ec::Sku.count", "Ec::SkuDimension.count", "Ec::SkuBatch.count"] do
      importer.call
    end
  end
end
