require "test_helper"

class LayoutFoundationTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(4)
    I18n.locale = I18n.default_locale
    cookies.delete(:locale)
    @current_user = create_user_with_roles("layout-#{@token}@example.com", "manager")
    sign_in @current_user
  end

  teardown do
    UserRole.joins(:user).where("users.email = ?", @current_user.email).delete_all
    @current_user.destroy
  end

  test "html pages use erp shell and local esbuild assets" do
    get "/reports/inventory", headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "html[lang='zh-CN']"
    assert_select "body.erp-shell"
    assert_select "meta[name='turbo-cache-control'][content='no-preview']"
    assert_select "link[rel='stylesheet'][href^='/assets/application']"
    assert_select "script[type='module'][src^='/assets/application']"
    assert_no_match "cdn.jsdelivr.net", response.body
    assert_select ".erp-sidebar"
    assert_select ".erp-topbar"
    assert_select ".erp-brand__name", "Yuanlong ERP"
    assert_select ".erp-nav__link[aria-current='page']", text: "库存"
    assert_select ".locale-switcher[aria-label='语言切换']"
    assert_select ".locale-switcher__link[aria-current='page']", text: "中"
    assert_select "a.locale-switcher__link[href*='locale=en']", text: "EN"
    assert_select "a.locale-switcher__link[href*='locale=ru']", text: "RU"
  end

  test "application uses chinese i18n defaults" do
    assert_equal :zh, I18n.default_locale
    assert_includes I18n.available_locales, :zh
    assert_includes I18n.available_locales, :ru
    assert_equal "元隆 ERP", I18n.t("app.name")
    assert_equal "Юаньлун ERP", I18n.t("app.name", locale: :ru)
  end

  test "locale switcher supports russian and persists selected locale" do
    get "/reports/inventory", params: { locale: "ru" }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "html[lang='ru']"
    assert_select ".erp-topbar__heading", "Юаньлун ERP"
    assert_select ".erp-nav__link[aria-current='page']", text: "Склад"
    assert_select ".locale-switcher__link[aria-current='page']", text: "RU"
    assert_match(/locale=/, response.headers["Set-Cookie"])
  end

  test "locale parameter is applied before authentication redirect" do
    sign_out @current_user

    get "/reports/inventory", params: { locale: "ru" }, headers: { "Accept" => "text/html" }
    follow_redirect!

    assert_response :success
    assert_select "html[lang='ru']"
    assert_select ".erp-topbar__heading", "Юаньлун ERP"
    assert_select ".locale-switcher__link[aria-current='page']", text: "RU"
  end
end
