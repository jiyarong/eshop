module Erp
  class OperationTasksController < BaseController
    def index
      @tasks = Ec::OperationTask.order(created_at: :desc)
    end

    def show
      @task = Ec::OperationTask.find(params[:id])
    end
  end
end
