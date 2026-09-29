module Ec
  class SkuPlanningCycleLock
    TIME_ZONE = Ec::SkuOperationPlan::TIME_ZONE

    def self.acquire(sku:, period_start:, period_end: nil, rerun: false, **attributes)
      new(sku: sku, period_start: period_start, period_end: period_end, rerun: rerun, attributes: attributes).acquire
    end

    def initialize(sku:, period_start:, period_end: nil, rerun: false, attributes: {})
      @sku = sku
      @period_start = period_start.to_date
      @period_end = (period_end || @period_start + 6.days).to_date
      @rerun = rerun
      @attributes = attributes
    end

    def acquire
      @sku.with_lock do
        current = Ec::SkuPlanningCycle.current_for(sku: @sku, period_start: @period_start)
        return current if current && !@rerun

        next_revision = Ec::SkuPlanningCycle.where(sku: @sku, period_start: @period_start).maximum(:revision).to_i + 1
        current&.update!(is_current: false)
        attributes = @attributes.dup
        attributes[:started_at] ||= Time.current if attributes[:status].to_s == "generating"
        Ec::SkuPlanningCycle.create!(
          attributes.merge(
            sku: @sku,
            period_start: @period_start,
            period_end: @period_end,
            revision: next_revision,
            is_current: true
          )
        )
      end
    end
  end
end
