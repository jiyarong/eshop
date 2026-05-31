module Erp
  class BaseController < ApplicationController
    helper_method :erp_value

    private

    def erp_value(value)
      return "-" if value.nil? || value == ""
      return format("%.2f", value) if value.is_a?(Float) || value.is_a?(BigDecimal)

      value
    end
  end
end
