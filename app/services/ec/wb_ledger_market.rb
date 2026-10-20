module Ec
  # Which target market a WB sale belongs to. WB orders carry no buyer country; only the finance
  # ledger (`raw_wb_finance_details.report_type`) tells: 1 is Belarus-local, 2 is export to Russia.
  # A sale (one srid) sits in exactly one of them.
  module WbLedgerMarket
    REPORT_TYPE_MARKETS = { 1 => "by", 2 => "ru" }.freeze
    MARKET_REPORT_TYPES = REPORT_TYPE_MARKETS.invert.freeze

    # The report_type of a market ("ru" -> 2); nil for a market WB does not report.
    def self.report_type_for(market)
      MARKET_REPORT_TYPES[market.to_s.downcase]
    end

    def self.market_for(report_type)
      REPORT_TYPE_MARKETS[report_type.to_i]
    end

    # { srid => "ru" | "by" } for the srids that have a sale row in the ledger. A sale that is not
    # in the ledger yet (this week's) is simply absent: its market is not known.
    def self.markets_by_srid(srids)
      srids = Array(srids).compact.uniq
      return {} if srids.empty?

      RawWb::FinanceDetail
        .where(srid: srids)
        .where("seller_oper_name LIKE ?", "%#{RawWb::FinanceDetail::SALE_KEYWORD}%")
        .group(:srid)
        .pluck(:srid, Arel.sql("MIN(report_type)"))
        .filter_map { |srid, report_type| (market = market_for(report_type)) && [ srid, market ] }
        .to_h
    end
  end
end
