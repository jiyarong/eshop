require "test_helper"

class LayoutFoundationTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(4)
    I18n.locale = I18n.default_locale
    cookies.delete(:locale)
    @current_user = create_user_with_roles("layout-#{@token}@example.com", "manager")
    @current_user.update!(name: "布局用户 #{@token}")
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
    assert_select "link[rel='icon'][type='image/png'][href='/favicon.png']"
    assert_select "link[rel='stylesheet'][href^='/assets/application']"
    assert_select "script[type='module'][src^='/assets/application']"
    assert_no_match "cdn.jsdelivr.net", response.body
    assert_select ".app"
    assert_select ".sidebar"
    assert_select ".header"
    assert_select ".main"
    assert_select ".brand span", text: "Yuanlong ERP"
    assert_select ".sidebar-toggle[aria-label='折叠左侧菜单']"
    assert_select ".erp-sidebar"
    assert_select ".erp-topbar"
    assert_select ".erp-brand__name", "Yuanlong ERP"
    assert_select ".erp-nav__link[aria-current='page']", text: "库存"
    assert_select ".erp-nav__label", text: "SKU"
    assert_select ".erp-nav__label", text: "Draft & Testing"
    assert_select ".erp-nav__label", text: "运营报表", count: 0
    assert_select ".erp-nav__label", text: "ERP 管理", count: 0
    assert_select ".erp-nav__link[href='/erp/spus']", text: "SPU 管理"
    assert_select ".erp-nav__link[href='/erp/skus']", text: "SKU 管理"
    assert_select ".erp-nav__link[data-turbo-prefetch='false']", minimum: 1
    assert_select ".erp-nav__link:not([data-turbo-prefetch='false'])", 0
    assert_select ".topbar-dropdown.locale-switcher[aria-label='语言切换']"
    assert_select ".locale-switcher .topbar-dropdown__value", text: "中"
    assert_select ".locale-switcher__item[aria-current='page']", text: "中文"
    assert_select "a.locale-switcher__item[href*='locale=en']", text: "English"
    assert_select "a.locale-switcher__item[href*='locale=ru']", text: "Русский"
    assert_select ".page-translation-controls[data-controller='page-translation']"
    assert_select ".page-translation-controls[data-page-translation-target-locale-value='zh']"
    assert_select ".page-translation-controls summary[data-page-translation-target='summary']"
    assert_select ".page-translation-controls__title", text: "AI 翻译"
    assert_select ".page-translation-controls__summary-status", text: "未翻译"
    assert_select ".page-translation-controls__summary-status[data-json-error-label='翻译结果格式异常']"
    assert_select ".page-translation-controls__summary-status[data-no-change-label='翻译无变化']"
    assert_select "button[data-action='page-translation#translate']", text: "开始翻译"
    assert_select "button[data-action='page-translation#translate'][data-json-error-label='翻译结果格式异常']"
    assert_select "button[data-action='page-translation#translate'][data-no-change-label='翻译无变化']"
    assert_select "button[data-action='page-translation#showOriginal']", text: "查看原文"
    assert_select "button[data-action='page-translation#showTranslation']", text: "查看译文"
    assert_select ".erp-account-menu"
    assert_select ".erp-account-menu__email", text: @current_user.name
    assert_select ".erp-account-menu__panel a[href='/profile/password']", text: "修改密码"
    assert_select ".erp-account-menu__panel form[action='#{destroy_user_session_path}'][method='post'] button", text: "退出"
    assert_select ".erp-account-menu__panel form[action='#{destroy_user_session_path}'] input[name='_method'][value='delete']", 0
    assert_select ".erp-topbar__actions .erp-account-menu", 1
    assert_select ".erp-topbar__actions .erp-user", 0
  end

  test "application uses chinese i18n defaults" do
    assert_equal :zh, I18n.default_locale
    assert_includes I18n.available_locales, :zh
    assert_includes I18n.available_locales, :ru
    assert_equal "辕隆 ERP", I18n.t("app.name")
    assert_equal "Юаньлун ERP", I18n.t("app.name", locale: :ru)
  end

  test "topbar inner spans full width for right aligned controls" do
    css = Rails.root.join("app/assets/stylesheets/application.css").read

    assert_match(/\.hd-inner\s*\{[^}]*width:\s*100%/m, css)
  end

  test "javascript entry does not emit competing application css build" do
    js = Rails.root.join("app/javascript/application.js").read
    css = Rails.root.join("app/assets/stylesheets/application.css").read

    assert_no_match(/import\s+["'][^"']+\.css["']/, js)
    assert_includes css, '@import "flatpickr/dist/flatpickr.css";'
    assert_includes js, 'import CategorySelectorController from "./controllers/category_selector_controller";'
    assert_includes js, 'Stimulus.register("category-selector", CategorySelectorController);'
    assert_includes js, 'import PageTranslationController from "./controllers/page_translation_controller";'
    assert_includes js, 'Stimulus.register("page-translation", PageTranslationController);'
  end

  test "locale switcher supports russian and persists selected locale" do
    get "/reports/inventory", params: { locale: "ru" }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "html[lang='ru']"
    assert_select ".erp-topbar__heading", "Юаньлун ERP"
    assert_select ".erp-nav__link[aria-current='page']", text: "Склад"
    assert_select ".erp-nav__label", text: "SKU"
    assert_select ".erp-nav__label", text: "Draft & Testing"
    assert_select ".locale-switcher .topbar-dropdown__value", text: "RU"
    assert_select ".locale-switcher__item[aria-current='page']", text: "Русский"
    assert_match(/locale=/, response.headers["Set-Cookie"])
  end

  test "locale parameter is applied before authentication redirect" do
    sign_out @current_user

    get "/reports/inventory", params: { locale: "ru" }, headers: { "Accept" => "text/html" }
    follow_redirect!

    assert_response :success
    assert_select "html[lang='ru']"
    assert_select "body.auth-shell"
    assert_select ".erp-topbar", 0
    assert_select "h1", text: "Вход"
    assert_select ".locale-switcher__link[aria-current='page']", text: "RU"
  end

  test "sign in page uses auth layout with locale switcher" do
    sign_out @current_user

    get "/users/sign_in", params: { locale: "en" }, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "html[lang='en']"
    assert_select "body.auth-shell"
    assert_select "body.erp-shell", 0
    assert_select ".erp-sidebar", 0
    assert_select ".erp-topbar", 0
    assert_select ".auth-layout"
    assert_select ".auth-locale .locale-switcher[aria-label='Language']"
    assert_select ".page-translation-controls", 0
    assert_select ".auth-locale .locale-switcher__link[aria-current='page']", text: "EN"
    assert_select "a.locale-switcher__link[href*='locale=zh']", text: "中"
    assert_select "a.locale-switcher__link[href*='locale=ru']", text: "RU"
    assert_select "h1", text: "Sign in"
    assert_select "label[for='user_email']", text: "Email"
    assert_select "label[for='user_password']", text: "Password"
    assert_select "label[for='user_remember_me']", text: "Remember me"
    assert_select "form.auth-form[data-turbo='false'] input[type='submit'][value='Sign in']"
  end
end
