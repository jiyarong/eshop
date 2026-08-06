module Ec
  module Returns
    class Backfill
      SOURCES = {
        "ozon" => RawOzon::Return,
        "wb" => RawWb::GoodsReturn
      }.freeze

      def self.run(platform: nil, batch_size: 500)
        sources = platform ? { platform.to_s => SOURCES.fetch(platform.to_s) } : SOURCES

        sources.each_with_object({}) do |(source_platform, model), result|
          totals = { normalized: 0, missing_order: 0, missing_sku_product: 0 }
          model.find_in_batches(batch_size: batch_size) do |batch|
            batch_result = Ec::Returns::Sync.call(raw_records: batch)
            totals.each_key { |key| totals[key] += batch_result.fetch(key) }
          end
          result[source_platform] = totals
        end
      end
    end
  end
end
