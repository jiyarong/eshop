require "test_helper"

class RawOzonAdsCsvParserTest < ActiveSupport::TestCase
  test "parses historical CPC product report by date and SKU" do
    body = <<~CSV
      ;Кампания № 30339429, период 08.07.2026-22.07.2026
      День;sku;Название товара;Цена товара, ₽;Показы;Клики;CTR, %;Добавления в корзину;Средняя стоимость клика, ₽;Расход, ₽;Продано товаров;Продажи в продвижении, ₽;Продано товаров модели;Продажи в продвижении с заказов модели, ₽;ДРР, %;Заказано на сумму, ₽;ДРР общий, %;Дата добавления
      14.07.2026;4630818888;Lamp;3670,00;3644;117;3,21;9;4,23;495,27;0;0,00;0;0,00;0,00;10410,00;4,8;25.06.2026
    CSV

    row = RawOzon::Ads::CsvParser.cpc_product_history(body).sole
    assert_equal Date.new(2026, 7, 14), row[:stat_date]
    assert_equal "4630818888", row[:ozon_sku_id]
    assert_equal 3644, row[:impressions]
    assert_equal 117, row[:clicks]
    assert_equal 495.27, row[:spend].to_f
    assert_equal 10_410, row[:total_order_revenue].to_i
  end

  test "parses CPO selected report into separate CPO and combo measures" do
    body = <<~CSV
      Отчёт
      SKU;Артикул;Цена товара, ₽;Ставка, %;Ставка, ₽;"Расход (""Оплата за заказ""), ₽";"Расход (""Комбо-модель""), ₽";"Продажи в продвижении (""Оплата за заказ""), ₽";"Продажи в продвижении (""Комбо-модель""), ₽";"Продано товаров (""Оплата за заказ""), шт.";"Продано товаров (""Комбо-модель""), шт.";"ДРР в продвижении (""Оплата за заказ""), %"
      3002;TOWEL;10800,00;10;1080,00;2130,00;11763,60;21300,00;117636,00;2;11;10,0
    CSV

    row = RawOzon::Ads::CsvParser.cpo_selected_products(body).sole
    assert_equal "3002", row[:ozon_sku_id]
    assert_equal 2130, row[:cpo_spend].to_i
    assert_equal 11_763, row[:combo_spend].to_i
    assert_equal 21_300, row[:cpo_revenue].to_i
    assert_equal 117_636, row[:combo_revenue].to_i
    assert_equal 2, row[:cpo_orders]
    assert_equal 11, row[:combo_orders]
  end

  test "normalizes the extra quote layer in Ozon CPO selected headers" do
    body = <<~CSV
      SKU;"""Расход (""""Комбо-модель""""), ₽""";"""Продажи в продвижении (""""Комбо-модель""""), ₽""";"""Продано товаров (""""Комбо-модель""""), шт."""
      3002;11763,60;117636,00;11
    CSV

    row = RawOzon::Ads::CsvParser.cpo_selected_products(body).sole
    assert_equal 11_763, row[:combo_spend].to_i
    assert_equal 117_636, row[:combo_revenue].to_i
    assert_equal 11, row[:combo_orders]
  end

  test "parses CPO all report as daily aggregate without SKU" do
    body = <<~CSV
      ;Оплата за заказ
      Дата;Продвижение;Расход, ₽;Продажи из поиска, ₽;Продажи из рекомендаций, ₽;Заказы из поиска;Заказы из рекомендаций
      2026-07-22;Все товары;100,50;2000,00;3000,00;2;3
    CSV

    row = RawOzon::Ads::CsvParser.cpo_all_daily(body).sole
    assert_equal Date.new(2026, 7, 22), row[:stat_date]
    assert_equal 100.5, row[:spend].to_f
    assert_equal 5000, row[:ad_revenue].to_i
    assert_equal 5, row[:orders_count]
  end
end
