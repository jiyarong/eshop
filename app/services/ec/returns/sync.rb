module Ec
  module Returns
    class Sync
      NORMALIZERS = {
        "RawOzon::Return" => Ec::Returns::OzonNormalizer,
        "RawWb::GoodsReturn" => Ec::Returns::WbNormalizer
      }.freeze

      def self.call(raw_records:)
        result = { normalized: 0, missing_order: 0, missing_sku_product: 0 }

        Array(raw_records).each do |raw_record|
          normalizer = NORMALIZERS.fetch(raw_record.class.name)
          normalized_return = normalizer.new(raw_record).call
          result[:normalized] += 1
          result[:missing_order] += 1 unless normalized_return.order_id
          result[:missing_sku_product] += normalized_return.items.count { |item| item.sku_product_id.nil? }
        end

        result
      end
    end
  end
end
