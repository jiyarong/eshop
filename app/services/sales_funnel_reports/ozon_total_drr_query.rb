module SalesFunnelReports
  class OzonTotalDrrQuery
    COST_MODELS = %w[cpc cpc_history cpo combo cpo_all].freeze

    def self.spend_by_sku(account_id:, from_date:, to_date:)
      spend_by_sku_and_date(account_id:, from_date:, to_date:)
        .each_with_object(Hash.new { |hash, key| hash[key] = BigDecimal("0") }) do |((sku, _date), spend), totals|
          totals[sku] += spend
        end
    end

    def self.spend_by_sku_and_date(account_id:, from_date:, to_date:)
      rows = RawOzon::AdSkuDailyStat
        .where(account_id:, stat_date: from_date..to_date)
        .pluck(:ozon_sku_id, :ad_unit_id, :stat_date, :cost_model, :spend)

      rows.group_by { |sku, unit_id, date, _model, _spend| [sku.to_s, unit_id, date] }
        .each_with_object(Hash.new { |hash, key| hash[key] = BigDecimal("0") }) do |((_sku, _unit_id, _date), records), totals|
          sku = records.first.first.to_s
          date = records.first[2]
          has_cpc_history = records.any? { |record| record[3] == "cpc_history" }
          records.each do |_sku_id, _ad_unit_id, _stat_date, cost_model, spend|
            next unless cost_model.in?(COST_MODELS)
            next if cost_model == "cpc" && has_cpc_history

            totals[[sku, date]] += spend.to_d
          end
        end
    end
  end
end
