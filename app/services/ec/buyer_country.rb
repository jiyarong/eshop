module Ec
  # Which country an order's buyer is in, from the strongest signal the platform gives.
  #
  # WB:   the statistics order's country_name (raw_wb_stats_orders, matched by srid).
  # Ozon: 1. the posting's destination cluster (financial_data.cluster_to); Ozon's own cluster table
  #          (raw_ozon_warehouse_clusters) says which country each cluster is in, so a new cluster
  #          brings its country with it (the config file covers the few the table does not list);
  #       2. the buyer's city, looked up in config/buyer_places.yml (a city that is not there is
  #          unknown, never "not Belarus"; a name that exists in two countries is settled by the
  #          currency among its candidates only);
  #       3. the currency the buyer paid in, a weak last resort that can be switched off in the same
  #          file once a third market bills in rubles or Belarusian rubles.
  #
  # The stored value is an ISO 3166 alpha-2 code in ec_orders.buyer_country, with the signal in
  # ec_orders.buyer_country_source. A stronger source replaces a weaker one, never the other way.
  module BuyerCountry
    CONFIG_PATH = Rails.root.join("config/buyer_places.yml")
    # Weakest first: the position is the rank.
    SOURCES = %w[buyer_currency city ozon_cluster stats_order].freeze
    # The source at which an order of a platform is settled and no longer looked at.
    TOP_SOURCE = { "wb" => "stats_order", "ozon" => "ozon_cluster" }.freeze

    COUNTRY_CODES = {
      "Россия" => "RU", "Беларусь" => "BY", "Казахстан" => "KZ", "Армения" => "AM", "Кыргызстан" => "KG",
      "Таджикистан" => "TJ", "Узбекистан" => "UZ", "Грузия" => "GE", "Азербайджан" => "AZ", "Молдова" => "MD",
      "Туркменистан" => "TM", "Украина" => "UA"
    }.freeze

    Result = Data.define(:country, :source)

    class << self
      def rank(source)
        index = SOURCES.index(source.to_s)
        index ? index + 1 : 0
      end

      def code_for(country_name)
        COUNTRY_CODES[country_name.to_s.strip]
      end

      def wb(country_name)
        code = code_for(country_name)
        code && Result.new(code, "stats_order")
      end

      # table_countries: { cluster_name => country_name } from Ozon's cluster table. A cluster the table
      # does not list yet (Самара, Махачкала at the time of writing) is taken from the reviewed
      # `clusters` section of the config file.
      def ozon_cluster(cluster_name, table_countries)
        code = code_for(table_countries[cluster_name]) || config.fetch("clusters", {})[cluster_name.to_s]
        code && Result.new(code, "ozon_cluster")
      end

      # places: the buyer city names we have (the order's, the destination table's).
      def city(places, currency: nil)
        candidates = Array(places).filter_map { |place| place_countries[normalize_place(place)] }.first
        return if candidates.nil?

        countries = Array(candidates)
        country = countries.one? ? countries.first : countries.find { |code| code == currency_country(currency) }
        country && Result.new(country, "city")
      end

      def currency(currency_code)
        return unless settings.fetch("currency_fallback", true)

        country = currency_country(currency_code)
        country && Result.new(country, "buyer_currency")
      end

      def currency_country(currency_code)
        settings.fetch("currency_countries", {})[currency_code.to_s.upcase]
      end

      # "г. Минск", "МИНСК ", "Могилёв": one key per place.
      def normalize_place(name)
        name.to_s.downcase.tr("ё", "е").sub(/\A\s*(город|г|пос|п|д|агрогородок|аг)\.?\s+/, "").gsub(/[^[:alnum:]\s-]/, "").squish
      end

      def place_countries
        config.fetch("cities", {})
      end

      def settings
        config.fetch("settings", {})
      end

      def reload!
        @config = nil
      end

      private

      def config
        @config ||= File.exist?(CONFIG_PATH) ? YAML.load_file(CONFIG_PATH) : {}
      end
    end
  end
end
