require "test_helper"
require "nokogiri"

class InventoryVolumeSummaryCardsTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(4).upcase
    @current_user = create_user_with_roles("inventory-summary-#{@token.downcase}@example.com", "manager")
    sign_in @current_user
  end

  teardown do
    sku_codes = Ec::Sku.with_deleted.where("sku_code LIKE ?", "SUM-%-#{@token}").pluck(:sku_code)
    Ec::SkuCost.where(sku_code: sku_codes).delete_all
    Ec::SkuBatch.where(sku_code: sku_codes).delete_all
    Ec::Sku.with_deleted.where(sku_code: sku_codes).delete_all
    UserRole.joins(:user).where("users.email LIKE ?", "inventory-summary-#{@token.downcase}%").delete_all
    User.where("email LIKE ?", "inventory-summary-#{@token.downcase}%").delete_all
  end

  test "inventory report renders filtered volume summary across pagination and ignores invalid contributions" do
    skus = 12.times.map do |index|
      Ec::Sku.create!(
        sku_code: format("SUM-%02d-%s", index, @token),
        product_name: "汇总商品#{index}",
        is_active: true
      )
    end

    row_payloads = skus.index_with do |sku|
      {
        sku_code: sku.sku_code,
        product_name: sku.product_name,
        product_name_ru: nil,
        incoming_quantity: 0,
        book_stock: 0,
        platform_stock: 0,
        available_stock: 0,
        unit_volume_l: nil,
        daily_sales_velocity: nil,
        turnover_days: nil,
        turnover_days_with_procurement: nil,
        cache_updated_at: Time.zone.parse("2026-07-04 10:00:00")
      }
    end

    row_payloads[skus[0]].merge!(incoming_quantity: 10, unit_volume_l: BigDecimal("1.0"))
    row_payloads[skus[1]].merge!(book_stock: 5, unit_volume_l: BigDecimal("2.0"))
    row_payloads[skus[10]].merge!(platform_stock: 3, available_stock: 4, unit_volume_l: BigDecimal("1.5"))
    row_payloads[skus[11]].merge!(incoming_quantity: -9, unit_volume_l: BigDecimal("5.0"))

    fake_query_factory = lambda do |sku|
      Object.new.tap do |query|
        query.define_singleton_method(:call) do
          row_payloads.fetch(sku)
        end
      end
    end

    fake_velocity_factory = lambda do |sku_codes:, date_to:, time_zone:|
      Object.new.tap do |query|
        query.define_singleton_method(:call) do
          sku_codes.index_with { |_| {} }
        end
      end
    end

    with_stubbed_constructor(Ec::InventoryPageRowQuery, fake_query_factory) do
      with_stubbed_constructor(Ec::InventoryVelocityMetricsQuery, fake_velocity_factory) do
        get "/reports/inventory", params: { sku: "sum-", page: 2 }, headers: { "Accept" => "text/html" }
      end
    end

    assert_response :success
    document = Nokogiri::HTML(response.body)
    report_sections = document.css(".report-stack > section")
    summary_section = document.at_css(".report-stack > section.inventory-volume-summary")
    table_section = document.at_css(".report-stack > section .inventory-list-table")&.ancestors("section")&.first

    assert summary_section, "expected inventory volume summary block to render"
    assert table_section, "expected inventory table panel to render"
    assert_operator report_sections.index(summary_section), :<, report_sections.index(table_section)

    summary_cards = summary_section.css(".weekly-profit-summary-card")
    assert_equal 4, summary_cards.size

    expected_cards = [
      [I18n.t("reports.inventory.fields.pending_stock"), "0.0100 m³"],
      [I18n.t("reports.inventory.fields.book_available_stock"), "0.0100 m³"],
      [I18n.t("reports.inventory.fields.platform_stock"), "0.0045 m³"],
      [I18n.t("reports.inventory.fields.overseas_available_stock"), "0.0060 m³"]
    ]

    expected_cards.each do |label, value|
      card = summary_cards.find { |node| node.at_css(".summary-label")&.text&.strip == label }
      assert card, "expected summary card for #{label}"
      assert_equal value, card.at_css(".summary-value")&.text&.strip
    end

    assert_select "tbody tr.inventory-list-table__row", count: 2
    assert_select "tbody tr.inventory-list-table__row td:nth-child(1) .inventory-list-table__sku-link", skus[10].sku_code
    assert_select "tbody tr.inventory-list-table__row td:nth-child(1) .inventory-list-table__sku-link", skus[11].sku_code
  end

  test "inventory report recalculates filtered volume summary on every request" do
    sku = Ec::Sku.create!(
      sku_code: "SUM-CACHE-#{@token}",
      product_name: "缓存商品",
      is_active: true
    )

    row_payload = {
      sku_code: sku.sku_code,
      product_name: sku.product_name,
      product_name_ru: nil,
      incoming_quantity: 10,
      book_stock: 5,
      platform_stock: 3,
      available_stock: 4,
      unit_volume_l: BigDecimal("1.5"),
      daily_sales_velocity: nil,
      turnover_days: nil,
      turnover_days_with_procurement: nil,
      cache_updated_at: Time.zone.parse("2026-07-04 10:00:00")
    }

    summary_builder_calls = 0
    fake_query_factory = lambda do |requested_sku|
      Object.new.tap do |query|
        query.define_singleton_method(:call) do
          row_payload
        end
      end
    end
    fake_velocity_factory = lambda do |sku_codes:, date_to:, time_zone:|
      Object.new.tap do |query|
        query.define_singleton_method(:call) do
          sku_codes.index_with { |_| {} }
        end
      end
    end
    summary_output = {
      pending_stock_volume_m3: BigDecimal("0.015"),
      book_available_stock_volume_m3: BigDecimal("0.0075"),
      platform_stock_volume_m3: BigDecimal("0.0045"),
      overseas_available_stock_volume_m3: BigDecimal("0.006")
    }
    summary_builder_stub = lambda do |rows|
      summary_builder_calls += 1
      summary_output
    end

    with_stubbed_constructor(Ec::InventoryPageRowQuery, fake_query_factory) do
      with_stubbed_constructor(Ec::InventoryVelocityMetricsQuery, fake_velocity_factory) do
        with_stubbed_method(Ec::InventoryVolumeSummaryBuilder, :call, summary_builder_stub) do
          get "/reports/inventory", params: { sku: "cache-#{@token.downcase}" }, headers: { "Accept" => "text/html" }
          assert_response :success
          assert_summary_card_value(I18n.t("reports.inventory.fields.pending_stock"), "0.0150 m³")

          summary_output = {
            pending_stock_volume_m3: BigDecimal("0.1111"),
            book_available_stock_volume_m3: BigDecimal("0.2222"),
            platform_stock_volume_m3: BigDecimal("0.3333"),
            overseas_available_stock_volume_m3: BigDecimal("0.4444")
          }

          sign_in @current_user
          get "/reports/inventory", params: { sku: "cache-#{@token.downcase}" }, headers: { "Accept" => "text/html" }
          assert_response :success
          assert_summary_card_value(I18n.t("reports.inventory.fields.pending_stock"), "0.1111 m³")
        end
      end
    end

    assert_operator summary_builder_calls, :>=, 2
  end

  private

  def with_stubbed_constructor(klass, replacement)
    simple_stubs = ActiveSupport::Testing::SimpleStubs.new
    simple_stubs.stub_object(klass, :new, &replacement)
    yield
  ensure
    simple_stubs&.unstub_all!
  end

  def with_stubbed_method(object, method_name, replacement)
    simple_stubs = ActiveSupport::Testing::SimpleStubs.new
    simple_stubs.stub_object(object, method_name, &replacement)
    yield
  ensure
    simple_stubs&.unstub_all!
  end

  def assert_summary_card_value(label, value)
    document = Nokogiri::HTML(response.body)
    summary_cards = document.css(".inventory-volume-summary .weekly-profit-summary-card")
    card = summary_cards.find { |node| node.at_css(".summary-label")&.text&.strip == label }

    assert card, "expected summary card for #{label}"
    assert_equal value, card.at_css(".summary-value")&.text&.strip
  end
end
