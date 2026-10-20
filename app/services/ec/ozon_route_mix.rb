module Ec
  # Where our Ozon units travel, as shares of the units of the same fulfilment (fbo / fbs) and buyer market
  # (ru / by): config/ozon_route_mix.yml, generated from the orders by script/generate_ozon_route_mix.rb.
  # Ec::LogisticsFormula weights Ozon's route tariff with it.
  module OzonRouteMix
    PATH = Rails.root.join("config/ozon_route_mix.yml")

    class << self
      # => [[origin_cluster_name, destination_cluster_name, share], ...]; empty when the file has nothing for
      # this fulfilment and market (the caller then falls back to the plain average of all routes).
      def routes(delivery_mode, market)
        by_origin = config.dig(delivery_mode.to_s.downcase, market.to_s.downcase) || {}
        by_origin.flat_map do |origin, destinations|
          destinations.map { |destination, share| [ origin.to_s, destination.to_s, BigDecimal(share.to_s) ] }
        end
      end

      def reset!
        @config = nil
      end

      private

      def config
        @config ||= File.exist?(PATH) ? YAML.load_file(PATH) || {} : {}
      end
    end
  end
end
