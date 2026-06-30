require "test_helper"

module Ec
  class OperationLogTest < ActiveSupport::TestCase
    setup do
      @token = SecureRandom.hex(4).upcase
      @user = User.create!(
        email: "audit-#{@token.downcase}@example.com",
        password: "password123",
        password_confirmation: "password123"
      )
      Current.user = @user
    end

    teardown do
      Current.user = nil if defined?(Current)
      Ec::OperationLog.where(record_type: ["Ec::Sku", "Ec::Store"]).delete_all if defined?(Ec::OperationLog)
      Ec::Sku.with_deleted.where(sku_code: "AUDIT-#{@token}").delete_all
      Ec::Store.where(store_name: "审计店铺 #{@token}").delete_all
      @user&.destroy
    end

    test "records one update log with current user and JSON array changeset" do
      sku = Ec::Sku.create!(sku_code: "AUDIT-#{@token}", product_name: "旧名称", is_active: true)

      assert_difference "Ec::OperationLog.count", 1 do
        sku.update!(product_name: "新名称", memo: "新备注")
      end

      log = Ec::OperationLog.order(:created_at).last
      assert_equal @user, log.user
      assert_equal "Ec::Sku", log.record_type
      assert_equal sku.id, log.record_id
      assert_equal "update", log.action
      assert_equal [
        { "field" => "product_name", "from" => "旧名称", "to" => "新名称" },
        { "field" => "memo", "from" => nil, "to" => "新备注" }
      ], log.changeset
    end

    test "does not record changes outside the configured audit attributes" do
      store = Ec::Store.create!(
        platform: "ozon",
        store_name: "审计店铺 #{@token}",
        company_type: "general"
      )

      assert_no_difference "Ec::OperationLog.count" do
        store.touch
      end
    end
  end
end
