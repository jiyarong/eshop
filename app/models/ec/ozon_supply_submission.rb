module Ec
  class OzonSupplySubmission < ApplicationRecord
    self.table_name = "ec_ozon_supply_submissions"

    STATES = %w[queued draft_submitting calculating warehouse_required loading_timeslots timeslot_required order_queued order_submitting creating syncing cargoes finalizing completed failed review_required cancelled].freeze
    RUNNING_STATES = %w[queued draft_submitting calculating loading_timeslots order_queued order_submitting creating syncing cargoes finalizing].freeze
    READ_STATES = %w[calculating loading_timeslots creating syncing cargoes finalizing].freeze

    belongs_to :pallet_plan, class_name: "Ec::PalletPlan"
    validates :request_key, presence: true, uniqueness: true
    validates :state, inclusion: { in: STATES }

    def running?
      state.in?(RUNNING_STATES)
    end

    def draft_expired?
      data["draft_created_at"].present? && Time.iso8601(data.fetch("draft_created_at")) < 30.minutes.ago
    end

    def retryable?
      state == "failed" && data["resume_state"].in?(READ_STATES)
    end

    def cancellable?
      (!data["order_attempted"] || data["order_failed"]) && !state.in?(%w[draft_submitting completed cancelled])
    end

    def warehouse_selectable?
      state.in?(%w[warehouse_required timeslot_required]) || state == "failed" && (data["resume_state"] == "loading_timeslots" || data["order_failed"])
    end

    def lock_name
      "ozon_supply_submission:#{id}"
    end
  end
end
