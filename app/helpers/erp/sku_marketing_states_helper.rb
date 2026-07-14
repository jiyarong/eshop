module Erp::SkuMarketingStatesHelper
  def sku_marketing_strategy_label(marketing_state)
    return "-" unless marketing_state&.strategy_key

    t("erp.sku_marketing_states.strategies.#{marketing_state.strategy_key}")
  end

  def sku_marketing_changed_by(marketing_state)
    marketing_state.changed_by&.display_name.presence || "-"
  end
end
