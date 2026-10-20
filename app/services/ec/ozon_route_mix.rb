module Ec
  # Where our Ozon units travel, by fulfilment (fbo / fbs) and buyer market (ru / by): config/ozon_route_mix.yml,
  # generated from the orders by script/generate_ozon_route_mix.rb. A scenario's fixed freight is the SIMPLE average of
  # the tariff of its most used routes: the TOP_ROUTES busiest origin -> destination routes of its fulfilment and
  # market (top_routes in the file: 40 for FBO, 20 for FBS). Checked against the real outbound bills, on routes picked
  # from earlier orders only (docs/sku_workbench_v2/14_场景扩展与可见性.md, section 13): FBO top 40 is 6% above the bills,
  # FBS top 20 (all 20 routes it has) 8% above, so a fixed-formula profit is not the optimistic one.
  module OzonRouteMix
    PATH = Rails.root.join("config/ozon_route_mix.yml")
    DEFAULT_TOP_ROUTES = { "fbo" => 40, "fbs" => 20 }.freeze

    class << self
      # => [[origin_cluster_name, destination_cluster_name, 1], ...] (equal weights); empty when the file has
      # nothing for this fulfilment and market (the caller then falls back to the plain average of all routes).
      def routes(delivery_mode, market)
        mode = delivery_mode.to_s.downcase
        by_origin = config.dig(mode, market.to_s.downcase) || {}
        ranked = by_origin.flat_map do |origin, destinations|
          destinations.map { |destination, share| [ origin.to_s, destination.to_s, BigDecimal(share.to_s) ] }
        end.sort_by { |_, _, share| -share }
        ranked.first(top_routes(mode)).map { |origin, destination, _| [ origin, destination, BigDecimal("1") ] }
      end

      def top_routes(mode)
        Integer(config.dig("top_routes", mode.to_s) || DEFAULT_TOP_ROUTES.fetch(mode.to_s, 20))
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
