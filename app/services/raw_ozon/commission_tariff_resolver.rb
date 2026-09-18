module RawOzon
  class CommissionTariffResolver
    FIELD_BY_DELIVERY_MODE = {
      "fbo" => "sales_percent_fbo",
      "fbp" => "sales_percent_fbp",
      "fbs" => "sales_percent_fbs",
      "rfbs" => "sales_percent_rfbs"
    }.freeze

    class ResolutionError < StandardError
      attr_reader :code

      def initialize(code)
        @code = code
        super(code.to_s)
      end
    end

    def rate_for(account_id:, ozon_product_id:, delivery_mode:)
      field = FIELD_BY_DELIVERY_MODE[delivery_mode.to_s]
      raise ResolutionError.new(:unsupported_delivery_mode) unless field

      commissions = RawOzon::ProductPrice
        .where(account_id: account_id, ozon_product_id: ozon_product_id)
        .pick(:commissions)
      raise ResolutionError.new(:missing_commission_rate) unless commissions

      value = commissions[field]
      raise ResolutionError.new(:missing_commission_rate) if value.nil?

      BigDecimal(value.to_s) / BigDecimal(100)
    end
  end
end
