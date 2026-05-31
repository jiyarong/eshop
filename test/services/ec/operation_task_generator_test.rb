require "test_helper"

class Ec::OperationTaskGeneratorTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(4).upcase
    @sku = Ec::Sku.create!(sku_code: "TASK-#{@token}", product_name: "任务测试 SKU")
    @inventory = Ec::InventoryTotal.create!(
      sku_code: @sku.sku_code,
      total_received: 100,
      total_supply: 98,
      total_stock: 2,
      total_sold: 80,
      total_fbs: 0,
      synced_at: Time.zone.now
    )
  end

  teardown do
    Ec::OperationTask.where(sku_code: @sku.sku_code).delete_all if defined?(Ec::OperationTask)
    Ec::InventoryTotal.where(sku_code: @sku.sku_code).delete_all
    @sku.destroy
  end

  test "creates replenish task for low available inventory" do
    tasks = Ec::OperationTaskGenerator.new(sku_code: @sku.sku_code).call

    assert_equal 1, tasks.size
    assert_equal "replenish", tasks.first.task_type
    assert_equal "open", tasks.first.status
  end
end
