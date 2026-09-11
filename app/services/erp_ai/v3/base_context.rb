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
          sku_products: ErpAI::V2::PlatformProductsContext.new(sku_products: sku.sku_products).call
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
