module Ec
  class ProfitCalculator
    FORMULA_VERSION = "excel_baseline_v4"
    def self.call(platform:, parameter_context: {}, inputs: {})
      calculator = { "wb" => ProfitCalculators::Wb, "ozon" => ProfitCalculators::Ozon }[platform.to_s]
      return error("unsupported_platform") unless calculator
      calculator.call(parameter_context: parameter_context.to_h, inputs: inputs.to_h)
    end
    def self.error(code) = { errors: [ code ], warnings: [], formula_version: FORMULA_VERSION }
  end
end
