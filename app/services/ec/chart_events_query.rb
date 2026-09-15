module Ec
  # Aggregates events from different domain models into one chart-event contract.
  #
  # Inputs:
  # - sku: required Ec::Sku whose events are requested.
  # - from_time/to_time: required half-open time range [from_time, to_time).
  # - user_time_zone: time zone used to produce event_date and occurred_at.
  # - level: :sku for an SKU-wide chart, or :listing for an SKU + store chart.
  # - store: required for :listing; ignored by SKU-wide providers at :sku level.
  # - sku_product: optional narrower listing constraint within the selected store.
  #
  # Output:
  # An array of normalized hashes, sorted by occurred_at and key. Every event has:
  # - key/source_type/event_type: globally stable identity and source information.
  # - occurred_at/event_date: chart position in the requested user time zone.
  # - chart_levels: levels where the event is allowed to appear (sku/listing).
  # - sku_id/store_id/sku_product_id: event ownership; store/listing values may be nil.
  # - title/source_label/context_label/summary/details: source-neutral display data.
  #
  # Providers own source-specific querying, visibility rules, and normalization. Add
  # future event sources to PROVIDERS instead of teaching charts about domain models.
  class ChartEventsQuery
    PROVIDERS = [
      Ec::ChartEvents::OperationActionChartProvider,
      Ec::ChartEvents::SkuLifecycleEventChartProvider
    ].freeze

    def self.run(...)
      new(...).call
    end

    def initialize(sku:, from_time:, to_time:, user_time_zone:, level:, store: nil, sku_product: nil)
      level = level.to_sym
      raise ArgumentError, "level must be :sku or :listing" unless %i[sku listing].include?(level)
      raise ArgumentError, "store is required for listing-level chart events" if level == :listing && store.blank?

      @arguments = { sku:, from_time:, to_time:, user_time_zone:, level:, store:, sku_product: }
    end

    def call
      events = PROVIDERS.flat_map { |provider| provider.call(**@arguments) }
      events.sort_by { |event| [ event[:occurred_at], event[:key] ] }
    end
  end
end
