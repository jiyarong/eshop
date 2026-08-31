require "test_helper"

class RawWb::OrderClusterResolverTest < ActiveSupport::TestCase
  test "maps buyer federal districts to warehouse report clusters" do
    stats_order = RawWb::StatsOrder.new(
      oblast_okrug_name: "Сибирский федеральный округ",
      region_name: "Новосибирская область",
      country_name: "Россия"
    )

    assert_equal "Дальневосточный и Сибирский", RawWb::OrderClusterResolver.cluster_to(stats_order)
  end

  test "falls back to supported non-Russian destinations" do
    armenia = RawWb::StatsOrder.new(region_name: "Ереван", country_name: "Армения")
    belarus = RawWb::StatsOrder.new(region_name: "Минск", country_name: "Беларусь")

    assert_equal "Армения", RawWb::OrderClusterResolver.cluster_to(armenia)
    assert_equal "Беларусь", RawWb::OrderClusterResolver.cluster_to(belarus)
  end
end
