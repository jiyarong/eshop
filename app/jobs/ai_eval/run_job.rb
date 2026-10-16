module AiEval
  class RunJob < ApplicationJob
    queue_as :default

    def perform(run_id)
      RunExecutor.call(run: RunRecord.find(run_id))
    end
  end
end
