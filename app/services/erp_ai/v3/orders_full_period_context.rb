module ErpAI
  module V3
    class OrdersFullPeriodContext < ErpAI::V2::OrdersFullPeriodContext
      private

      def row_for(item)
        super.merge(
          commission_base_unit_price: item.commission_base_unit_price,
          commission_base_currency_code: item.commission_base_currency_code,
          buyer_paid_unit_price: item.buyer_paid_unit_price,
          buyer_currency_code: item.buyer_currency_code,
          # Deprecated: no longer written; use commission_base_unit_price.
          seller_discount_unit_price: item.seller_discount_unit_price,
          seller_discount_currency_code: item.seller_discount_currency_code
        )
      end
    end
  end
end
