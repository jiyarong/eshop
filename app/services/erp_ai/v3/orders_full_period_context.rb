module ErpAI
  module V3
    class OrdersFullPeriodContext < ErpAI::V2::OrdersFullPeriodContext
      private

      def row_for(item)
        super.merge(
          buyer_paid_unit_price: item.buyer_paid_unit_price,
          buyer_currency_code: item.buyer_currency_code,
          seller_discount_unit_price: item.seller_discount_unit_price,
          seller_discount_currency_code: item.seller_discount_currency_code
        )
      end
    end
  end
end
