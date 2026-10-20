module Ec
  module PalletPlans
    class Workflow
      ORDER = %w[draft reserved packing packed dispatched closed].freeze
      def initialize(plan:, user:)
        @plan, @user = plan, user
      end

      def confirm!
        transition!("reserved")
      end

      def advance!(status, platform_check_note: nil)
        raise Error.new(:invalid_status) unless status.to_s.in?(ORDER)
        raise Error.new(:platform_check_required) if status.to_s == "dispatched" && platform_check_note.to_s.strip.blank?
        transition!(status.to_s, platform_check_note: platform_check_note)
      end

      def cancel!
        @plan.with_lock do
          raise Error.new(:submission_in_progress) if @plan.ozon_supply_submission && !@plan.ozon_supply_submission.state.in?(%w[completed cancelled])
          raise Error.new(:invalid_status) if %w[closed cancelled].include?(@plan.status)
          @plan.update!(status: "cancelled")
        end
        @plan
      end

      def bind!(number)
        raise Error.new(:invalid_status) unless @plan.active?
        raise Error.new(:submission_in_progress) unless @plan.manual_supply_binding_allowed?
        OzonReconciler.new(plan: @plan).bind!(number)
      end

      def refresh!
        Ec::PalletPlanSyncJob.perform_later(plan_id: @plan.id)
        @plan
      end

      private
      def transition!(status, platform_check_note: nil)
        @plan.with_lock do
          raise Error.new(:submission_in_progress) if @plan.ozon_supply_submission && !@plan.ozon_supply_submission.state.in?(%w[completed cancelled])
          raise Error.new(:invalid_status) unless @plan.status == "draft" && status == "reserved" || ORDER.index(status).to_i == ORDER.index(@plan.status).to_i + 1
          attrs = { status: status }
          attrs[:confirmed_at] = Time.current if status == "reserved"
          attrs[:dispatched_at] = Time.current if status == "dispatched"
          attrs[:closed_at] = Time.current if status == "closed"
          attrs[:platform_check_note] = platform_check_note if platform_check_note
          @plan.update!(attrs)
        end
        @plan
      end
    end
  end
end
