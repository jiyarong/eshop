module Ec
  # The commission rate of one scenario's platform and fulfilment mode from the platform's own tariff data, or
  # nothing: a rate is only given when every active listing of the SKU on that platform resolves to the same
  # official rate. A listing without a tariff, or listings with different rates, leave the rate empty with the reason,
  # so a calculation never rests on a rate somebody had to guess. Built on Ec::SkuOfficialCommissionRateQuery,
  # which the pricing page's "official commission" button also uses.
  class SkuOfficialCommissionRate
    # => { rate: BigDecimal | nil, reason: nil | "no_listings" | "unresolved_listings" | "rates_differ" }
    def self.call(sku:, platform:, delivery_mode:)
      payload = Ec::SkuOfficialCommissionRateQuery.run(sku:, platform:, delivery_mode:)
      return { rate: nil, reason: "no_listings" } if payload.fetch(:binding_count).zero?
      return { rate: nil, reason: "unresolved_listings" } if payload.fetch(:unresolved_count).positive?

      rates = payload.fetch(:rates)
      return { rate: nil, reason: "rates_differ" } unless rates.one?

      { rate: BigDecimal(rates.first.fetch(:rate)), reason: nil }
    rescue ArgumentError
      { rate: nil, reason: "unsupported" }
    end
  end
end
