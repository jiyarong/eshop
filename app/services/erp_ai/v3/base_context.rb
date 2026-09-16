module ErpAI
  module V3
    class BaseContext
      def initialize(sku:)
        @sku = sku
      end

      def call
        marketing_state = sku.current_marketing_state

        {
          spu_code: sku.master_sku&.master_sku_code,
          spu_id: sku.master_sku_id,
          related_spu_sku_codes: related_spu_sku_codes,
          current_stage: marketing_state&.stage&.upcase,
          current_grade: marketing_state&.grade,
          sku_products: sku.sku_products.order(:id).map do |sku_product|
            {
              store_id: sku_product.store_id,
              platform: sku_product.platform,
              product_id: sku_product.product_id,
              offer_id: sku_product.offer_id
            }
          end
        }
      end

      private

      attr_reader :sku

      def related_spu_sku_codes
        return [] unless sku.master_sku

        sku.master_sku.skus.filter_map do |related_sku|
          related_sku.sku_code unless related_sku.id == sku.id
        end.sort
      end
    end
  end
end
