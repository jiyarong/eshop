require "test_helper"

module Ec
  class SkuOperatorAssignmentTest < ActiveSupport::TestCase
    setup do
      @token = SecureRandom.hex(6).upcase
      @sku = Ec::Sku.create!(sku_code: "SKU-OP-#{@token}", product_name: "Operator assignment")
      @operator = User.create!(email: "sku-operator-#{@token.downcase}@example.com", password: "password123")
      @other_operator = User.create!(email: "sku-other-operator-#{@token.downcase}@example.com", password: "password123")
    end

    teardown do
      Ec::SkuOperatorAssignment.where(sku_code: @sku&.sku_code).delete_all
      Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
      User.where(id: [@operator&.id, @other_operator&.id]).delete_all
    end

    test "assigns an operator to an sku without platform listings" do
      Ec::SkuOperatorAssignment.create!(sku: @sku, user: @operator)

      assert_equal @operator, @sku.reload.operator
      assert_includes @operator.reload.operated_skus, @sku
    end

    test "allows only one operator per sku" do
      Ec::SkuOperatorAssignment.create!(sku: @sku, user: @operator)

      duplicate = Ec::SkuOperatorAssignment.new(sku: @sku, user: @other_operator)
      assert_not duplicate.valid?
      assert duplicate.errors.where(:sku_code, :taken).any?
    end
  end
end
