require "test_helper"

class Ec::PalletPlans::WorkflowTest < ActiveSupport::TestCase
  self.use_transactional_tests = true
  include ActiveJob::TestHelper

  setup do
    @token = SecureRandom.hex(6).upcase
    @user = User.create!(email: "pallet-workflow-#{@token.downcase}@example.com", password: "password123")
    @account = RawOzon::SellerAccount.create!(client_id: "pallet-workflow-#{@token}", api_key: "test", company_type: "general")
    @store = Ec::Store.create!(platform: "ozon", store_name: "Pallet workflow #{@token}", company_type: "general", ozon_raw_account_id: @account.id)
    @plan = Ec::PalletPlan.create!(store: @store, created_by: @user, macrolocal_cluster_id: 751, cluster_name: "Москва",
      status: "draft", from_date: Date.new(2026, 7, 1), to_date: Date.new(2026, 7, 28), target_days: 28, time_zone: "Asia/Shanghai")
  end

  test "refresh enqueues a plan-scoped sync with keyword arguments" do
    assert_enqueued_with(job: Ec::PalletPlanSyncJob, args: [{ plan_id: @plan.id }]) do
      Ec::PalletPlans::Workflow.new(plan: @plan, user: @user).refresh!
    end
  end

  test "requires a platform compliance note before dispatch" do
    workflow = Ec::PalletPlans::Workflow.new(plan: @plan, user: @user)
    workflow.confirm!
    workflow.advance!("packing")
    workflow.advance!("packed")

    error = assert_raises(Ec::PalletPlans::Error) { workflow.advance!("dispatched") }
    assert_equal :platform_check_required, error.key
  end
end
