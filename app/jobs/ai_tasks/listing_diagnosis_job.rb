module AITasks
  class ListingDiagnosisJob < ApplicationJob
    queue_as :default

    limits_concurrency to: 3,
      key: ->(*) { "listing_diagnoses" },
      duration: 1.hour

    def perform(suggestion_id, locale: I18n.default_locale.to_s)
      I18n.with_locale(locale) do
        ErpAI::ListingDiagnosisRunner.run(suggestion_id: suggestion_id)
      end
    end
  end
end
