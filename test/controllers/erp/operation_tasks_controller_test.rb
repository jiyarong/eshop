require "test_helper"

class Erp::OperationTasksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(4).upcase
    @sku = Ec::Sku.create!(sku_code: "TASK-PAGE-#{@token}", product_name: "任务页面 SKU")
    @task = Ec::OperationTask.create!(
      task_type: "replenish",
      status: "open",
      priority: "high",
      sku_code: @sku.sku_code,
      title: "#{@sku.sku_code} 库存不足，检查补货",
      reason: "总可售库存不足。",
      suggested_action: "检查补货。"
    )
  end

  teardown do
    Ec::OperationTask.where(id: @task.id).delete_all if defined?(Ec::OperationTask)
    @sku.destroy
  end

  test "index renders operation tasks" do
    get "/erp/operation_tasks", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", "运营任务"
    assert_select "td", @task.title
    assert_select "td", @sku.sku_code
  end

  test "show renders operation task detail" do
    get "/erp/operation_tasks/#{@task.id}", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", @task.title
    assert_select "dt", "建议动作"
  end
end
