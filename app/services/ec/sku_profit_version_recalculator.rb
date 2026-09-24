module Ec
  class SkuProfitVersionRecalculator
    def self.call(version)
      calculated_at = Time.current
      SkuProfitVersionPriceResolver.apply!(version)
      version.contexts.index_with do |context|
        result = SkuProfitCalculator.call_for_context(context)
        context.apply_calculation_result(result, calculated_at: calculated_at)
        result
      end
    end
  end
end
