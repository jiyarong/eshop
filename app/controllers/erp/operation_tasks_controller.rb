module Erp
  class OperationTasksController < BaseController
    def index
      @tasks = []
    end

    def show
      head :not_found
    end
  end
end
