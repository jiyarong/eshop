module Ec
  # The two ways a scenario's logistics cost is decided (ec_sku_profit_version_contexts.logistics_mode):
  #
  #   formula  the fixed formula, the same number for the same SKU whoever looks at it:
  #            WB   base rate x warehouse coefficient for the outbound leg, a flat 50 RUB return
  #                 (what WB really charges; decided 2026-10-20), i.e. no typed figures at all;
  #            Ozon the route tariff averaged over every route for the SKU's volume (the "use the route
  #                 average" figure of the tariff dialog), for the outbound and the return leg alike.
  #            Typed or applied real figures are ignored; they are reference only.
  #   actual   the typed or applied real figures (recent averages), as the workbench always worked.
  #
  # `apply` returns the inputs the calculator should use and what the formula says, so the page can show
  # the formula's figures next to the real ones.
  module LogisticsFormula
    MODES = %w[formula actual].freeze
    DEFAULT_MODE = "actual".freeze # a caller that does not say keeps the old behaviour
    WB_FIGURES = %w[outbound_logistics_rub return_logistics_rub wb_logistics_override_cny].freeze
    OZON_FIGURES = %w[outbound_logistics_rub return_logistics_rub].freeze

    class << self
      def mode_for(parameter_context)
        parameter_context.to_h.stringify_keys["logistics_mode"].to_s.presence_in(MODES) || DEFAULT_MODE
      end

      # => [inputs, { mode:, outbound_rub:, return_rub:, source: }]
      def apply(platform:, mode:, parameter_context:, inputs:)
        inputs = inputs.to_h.stringify_keys
        return [ inputs, { mode: mode, outbound_rub: nil, return_rub: nil, source: nil } ] unless mode == "formula"

        if platform.to_s.downcase == "wb"
          [ inputs.except(*WB_FIGURES), { mode: mode, outbound_rub: nil, return_rub: nil, source: "wb_coefficient" } ]
        else
          ozon_formula(inputs.except(*OZON_FIGURES), parameter_context.to_h.stringify_keys)
        end
      end

      # What the Ozon route tariff says for the inputs' volume, or nil without volume, price or tariff: the simple
      # average of the tariff of the scenario's busiest routes (Ec::OzonRouteMix: top 40 for FBO, top 20 for FBS, by
      # fulfilment and buyer market). A route the tariff does not list drops out. Without routes for the scenario it
      # is the plain average of every route.
      def ozon_route_average(inputs, parameter_context)
        volume = volume_l(inputs)
        return unless volume

        snapshot = RawOzon::LogisticsTariffSnapshot.current_for(market_code: "ru")
        return unless snapshot

        column = tariff_column(parameter_context["delivery_mode"], inputs)
        band = snapshot.logistics_tariffs.for_volume(volume)
        routes = Ec::OzonRouteMix.routes(parameter_context["delivery_mode"].presence || "fbo", parameter_context["market"].presence || "ru")
        average = weighted_route_average(band, column, routes) || band.average(column)
        average&.to_d&.round(2)
      end

      private

      def weighted_route_average(band, column, routes)
        return if routes.empty?

        prices = band.where(origin_cluster_name: routes.map(&:first).uniq, destination_cluster_name: routes.map { |route| route[1] }.uniq)
          .pluck(:origin_cluster_name, :destination_cluster_name, column)
          .to_h { |origin, destination, price| [ [ origin, destination ], price.to_d ] }
        matched = routes.select { |origin, destination, _| prices.key?([ origin, destination ]) }
        total = matched.sum { |_, _, share| share }
        return unless total.positive?

        matched.sum { |origin, destination, share| prices.fetch([ origin, destination ]) * share } / total
      end

      def ozon_formula(inputs, parameter_context)
        rate = ozon_route_average(inputs, parameter_context)
        return [ inputs, { mode: "formula", outbound_rub: nil, return_rub: nil, source: nil } ] unless rate

        # The return leg costs what the way out does (the tariff dialog has always filled both).
        [ inputs.merge("outbound_logistics_rub" => rate, "return_logistics_rub" => rate),
          { mode: "formula", outbound_rub: rate, return_rub: rate, source: "ozon_route_average" } ]
      end

      def volume_l(inputs)
        dimensions = %w[length_cm width_cm height_cm].map { |key| BigDecimal(inputs[key].to_s, exception: false) }
        return if dimensions.any?(&:nil?) || dimensions.any?(&:negative?)

        dimensions.reduce(:*) / 1000
      end

      # FBS is cheaper under 300 RUB; FBO has one price.
      def tariff_column(delivery_mode, inputs)
        return :fbo_rub unless delivery_mode.to_s.downcase == "fbs"

        price = BigDecimal(inputs["commission_base_price_rub"].to_s, exception: false)
        price && price < 300 ? :fbs_under_300_rub : :fbs_over_300_rub
      end
    end
  end
end
