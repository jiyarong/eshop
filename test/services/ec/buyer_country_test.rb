require "test_helper"

class Ec::BuyerCountryTest < ActiveSupport::TestCase
  test "places are normalised to one key" do
    assert_equal "минск", Ec::BuyerCountry.normalize_place("Минск")
    assert_equal "минск", Ec::BuyerCountry.normalize_place("  г. МИНСК ")
    assert_equal "могилев", Ec::BuyerCountry.normalize_place("Могилёв")
    assert_equal "колодищи", Ec::BuyerCountry.normalize_place("агрогородок Колодищи")
    assert_equal "ростов-на-дону", Ec::BuyerCountry.normalize_place("Ростов-на-Дону")
    assert_equal "", Ec::BuyerCountry.normalize_place(nil)
  end

  test "country names become ISO codes, an unknown name stays unknown" do
    assert_equal "RU", Ec::BuyerCountry.code_for("Россия")
    assert_equal "BY", Ec::BuyerCountry.code_for("Беларусь")
    assert_equal "KZ", Ec::BuyerCountry.code_for("Казахстан")
    assert_nil Ec::BuyerCountry.code_for("Атлантида")
    assert_nil Ec::BuyerCountry.wb("Атлантида")
    assert_equal Ec::BuyerCountry::Result.new("KZ", "stats_order"), Ec::BuyerCountry.wb("Казахстан")
  end

  test "an Ozon cluster takes its country from Ozon's cluster table, or from the reviewed list when the table lacks it" do
    table = { "Беларусь" => "Беларусь", "Казань" => "Россия", "Алматы" => "Казахстан" }

    assert_equal Ec::BuyerCountry::Result.new("BY", "ozon_cluster"), Ec::BuyerCountry.ozon_cluster("Беларусь", table)
    assert_equal Ec::BuyerCountry::Result.new("KZ", "ozon_cluster"), Ec::BuyerCountry.ozon_cluster("Алматы", table)
    assert_equal Ec::BuyerCountry::Result.new("RU", "ozon_cluster"), Ec::BuyerCountry.ozon_cluster("Самара", table), "listed in config/buyer_places.yml"
    assert_nil Ec::BuyerCountry.ozon_cluster("Новый кластер", table), "a new cluster nobody classified is unknown, not Russian"
  end

  test "a place decides the country; an unknown place decides nothing; a name on both sides needs the currency to pick one" do
    assert_equal "BY", Ec::BuyerCountry.city([ "Новогрудок" ]).country
    assert_equal "RU", Ec::BuyerCountry.city([ "Москва" ]).country
    assert_equal "city", Ec::BuyerCountry.city([ "Москва" ]).source
    assert_nil Ec::BuyerCountry.city([ "Несуществующий" ])
    assert_nil Ec::BuyerCountry.city([ nil, "" ])
    assert_equal "BY", Ec::BuyerCountry.city([ "Иваново" ], currency: "BYN").country
    assert_equal "RU", Ec::BuyerCountry.city([ "Иваново" ], currency: "RUB").country
    assert_nil Ec::BuyerCountry.city([ "Иваново" ]), "Ivanovo exists in Russia and in Belarus"
    assert_nil Ec::BuyerCountry.city([ "Иваново" ], currency: "KZT"), "the currency only chooses among the candidates"
    assert_equal "BY", Ec::BuyerCountry.city([ nil, "Минск" ]).country, "the first place that is known wins"
  end

  test "the currency is a weak last resort that the config can switch off" do
    assert_equal Ec::BuyerCountry::Result.new("BY", "buyer_currency"), Ec::BuyerCountry.currency("BYN")
    assert_equal "RU", Ec::BuyerCountry.currency("rub").country
    assert_nil Ec::BuyerCountry.currency("KZT")

    begin
      Ec::BuyerCountry.instance_variable_set(:@config, { "settings" => { "currency_fallback" => false, "currency_countries" => { "BYN" => "BY" } } })
      assert_nil Ec::BuyerCountry.currency("BYN")
    ensure
      Ec::BuyerCountry.reload!
    end
    assert_equal "BY", Ec::BuyerCountry.currency("BYN").country
  end

  test "stronger sources outrank weaker ones" do
    ranks = Ec::BuyerCountry::SOURCES.map { |source| Ec::BuyerCountry.rank(source) }
    assert_equal ranks.sort, ranks
    assert_equal 0, Ec::BuyerCountry.rank(nil)
    assert Ec::BuyerCountry.rank("ozon_cluster") > Ec::BuyerCountry.rank("city")
    assert Ec::BuyerCountry.rank("city") > Ec::BuyerCountry.rank("buyer_currency")
    assert_includes Ec::BuyerCountry::SOURCES, Ec::BuyerCountry::TOP_SOURCE.fetch("wb")
    assert_includes Ec::BuyerCountry::SOURCES, Ec::BuyerCountry::TOP_SOURCE.fetch("ozon")
  end

  test "the places file is well formed: normalised keys, known country codes, ambiguous names listed with several" do
    codes = Ec::BuyerCountry::COUNTRY_CODES.values
    places = Ec::BuyerCountry.place_countries

    assert places.size > 500
    places.each do |key, value|
      assert_equal Ec::BuyerCountry.normalize_place(key), key, "#{key} is not a normalised key"
      Array(value).each { |code| assert_includes codes, code, "#{key}: #{code}" }
      assert_operator Array(value).size, :>=, 1
    end
    assert_equal %w[BY RU], places.fetch("иваново").sort
    Ec::BuyerCountry.send(:config).fetch("clusters").each_value { |code| assert_includes codes, code }
  end
end
