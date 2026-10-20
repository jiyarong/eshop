module Ec
  class OzonSupplySubmissionJob < ApplicationJob
    queue_as :default

    def perform(submission_id = nil)
      unless submission_id
        Ec::OzonSupplySubmission.where(state: Ec::OzonSupplySubmission::RUNNING_STATES).where(updated_at: ...1.minute.ago).find_each do |submission|
          self.class.perform_later(submission.id)
        end
        return
      end
      submission = Ec::OzonSupplySubmission.find_by(id: submission_id)
      return unless submission
      Ec::PalletPlans::OzonSupplyRunner.new(submission: submission).call
      self.class.set(wait: 15.seconds).perform_later(submission.id) if submission.reload.running?
    end
  end
end
