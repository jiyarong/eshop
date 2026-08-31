module RawWb
  class OrderClusterResolver
    FEDERAL_DISTRICT_CLUSTERS = {
      "Центральный" => "Центральный",
      "Приволжский" => "Приволжский",
      "Уральский" => "Уральский",
      "Северо-Западный" => "Северо-Западный",
      "Сибирский" => "Дальневосточный и Сибирский",
      "Дальневосточный" => "Дальневосточный и Сибирский",
      "Южный" => "Южный и Северо-Кавказский",
      "Северо-Кавказский" => "Южный и Северо-Кавказский"
    }.freeze
    REGION_CLUSTERS = {
      "Ереван" => "Армения",
      "Армения" => "Армения",
      "Минск" => "Беларусь",
      "Беларусь" => "Беларусь"
    }.freeze

    def self.resolve(stats_order, on: stats_order.order_date&.to_date || Date.current)
      {
        cluster_from: cluster_from(stats_order, on: on),
        cluster_to: cluster_to(stats_order)
      }
    end

    def self.cluster_from(stats_order, on:)
      RawWb::WarehouseNameResolver.resolve(
        account_id: stats_order.account_id,
        warehouse_name: stats_order.warehouse_name,
        on: on
      )&.region_name
    end

    def self.cluster_to(stats_order)
      district = stats_order.oblast_okrug_name.to_s.strip.sub(/ федеральный округ\z/, "")
      FEDERAL_DISTRICT_CLUSTERS[district] ||
        REGION_CLUSTERS[stats_order.region_name.to_s.strip] ||
        REGION_CLUSTERS[stats_order.country_name.to_s.strip]
    end
  end
end
