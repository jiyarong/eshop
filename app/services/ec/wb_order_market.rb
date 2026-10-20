module Ec
  # The target market of a WB order: the buyer's country as the statistics API reports it
  # (`raw_wb_stats_orders.country_name`, keyed by srid, available as soon as the order exists).
  # Russia is the "ru" market, Belarus the "by" market; any other country (Kazakhstan, Armenia ...)
  # is "other", a market the workbench has no scenario for.
  #
  # The ledger's report_type is NOT a market: its type 1 holds every non-Russian sale, but also the
  # cancelled and refused parcels of Russian buyers (307 of the 314 classified cancel legs in
  # Aug-Sep 2026), so a market taken from it would charge those parcels to Belarus.
  module WbOrderMarket
    COUNTRY_MARKETS = { "Россия" => "ru", "Беларусь" => "by" }.freeze
    MARKETS = COUNTRY_MARKETS.values.freeze

    # { srid => "ru" | "by" | "other" } for the srids that have a statistics order with a country.
    # An srid without one (a cancelled order the statistics never listed, a seller-return parcel
    # with its own srid) is simply absent: its market is not known.
    def self.markets_by_srid(srids)
      srids = Array(srids).compact.uniq
      return {} if srids.empty?

      RawWb::StatsOrder
        .where(srid: srids)
        .where.not(country_name: [ nil, "" ])
        .pluck(:srid, :country_name)
        .to_h { |srid, country| [ srid, COUNTRY_MARKETS.fetch(country.to_s.strip, "other") ] }
    end
  end
end
