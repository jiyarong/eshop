require "test_helper"

module Ec
  class SkuDeveloperAssignmentTest < ActiveSupport::TestCase
    setup do
      @token = SecureRandom.hex(4).upcase
      @user = User.create!(
        email: "sku-developer-#{@token.downcase}@example.com",
        password: "password123",
        password_confirmation: "password123"
      )
      @sku = Ec::Sku.create!(
        sku_code: "SKU-DEV-#{@token}",
        product_name: "开发绑定 SKU #{@token}",
        is_active: true
      )
      @store = Ec::Store.create!(
        platform: "ozon",
        store_name: "开发绑定店铺 #{@token}",
        company_type: "general",
        is_active: true
      )
      @sku_product = Ec::SkuProduct.create!(
        sku_code: @sku.sku_code,
        store: @store,
        product_id: "SKU-DEV-P-#{@token}",
        product_name: "开发绑定商品 #{@token}"
      )
    end

    teardown do
      Ec::SkuDeveloperAssignment.where(sku_code: @sku&.sku_code).delete_all
      Ec::SkuProduct.where(id: @sku_product&.id).delete_all
      Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
      Ec::Store.where(id: @store&.id).delete_all
      User.where(id: @user&.id).delete_all
    end

    test "developer assignments belong to sku and are visible from sku products" do
      Ec::SkuDeveloperAssignment.create!(sku: @sku, user: @user)

      assert_equal [@user], @sku.reload.developers
      assert_equal [@user], @sku_product.reload.developers
      assert_includes @user.reload.developed_skus, @sku
    end

    test "developer assignment is unique per sku and user" do
      Ec::SkuDeveloperAssignment.create!(sku: @sku, user: @user)
      duplicate = Ec::SkuDeveloperAssignment.new(sku: @sku, user: @user)

      assert_not duplicate.valid?
      assert duplicate.errors.where(:user_id, :taken).any?
    end
  end
end
