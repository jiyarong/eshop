require "test_helper"

module Erp
  class CategoriesControllerTest < ActionDispatch::IntegrationTest
    setup do
      @token = SecureRandom.hex(4)
      @current_user = create_user_with_roles("erp-categories-selector-#{@token}@example.com", "manager")
      sign_in @current_user

      @parent = Ec::Category.create!(
        source: "test",
        source_type: "category",
        source_id: source_id("parent"),
        origin_name: "Родитель #{@token}",
        origin_language: "ru",
        name_cn: "父级类目 #{@token}",
        name_en: "Parent #{@token}",
        name_ru: "Родитель #{@token}"
      )
      @child = Ec::Category.create!(
        source: "test",
        source_type: "subject",
        source_id: source_id("child"),
        parent: @parent,
        origin_name: "Дочерняя #{@token}",
        origin_language: "ru",
        name_cn: "子级类目 #{@token}",
        name_en: "Child #{@token}",
        name_ru: "Дочерняя #{@token}"
      )
    end

    teardown do
      Ec::Category.where(source: "test", source_id: [source_id("parent"), source_id("child")]).delete_all
      UserRole.joins(:user).where("users.email LIKE ?", "erp-categories-selector-#{@token}%").delete_all
      User.where("email LIKE ?", "erp-categories-selector-#{@token}%").delete_all
    end

    test "index returns top-level categories localized for current locale" do
      get "/erp/categories.json", params: { locale: "zh" }

      assert_response :success
      categories = response.parsed_body.fetch("categories")
      category = categories.find { |item| item.fetch("id") == @parent.id }

      assert category
      assert_equal "父级类目 #{@token}", category.fetch("name")
      assert_nil category.fetch("parent_id")
      assert_nil categories.find { |item| item.fetch("id") == @child.id }
    end

    test "index returns only second-level categories for parent_id" do
      get "/erp/categories.json", params: { parent_id: @parent.id, locale: "en" }

      assert_response :success
      categories = response.parsed_body.fetch("categories")

      assert_equal [@child.id], categories.map { |item| item.fetch("id") }
      assert_equal "Child #{@token}", categories.first.fetch("name")
      assert_equal @parent.id, categories.first.fetch("parent_id")
    end

    test "index searches categories without loading the whole tree" do
      get "/erp/categories.json", params: { q: "Child #{@token}", locale: "en" }

      assert_response :success
      categories = response.parsed_body.fetch("categories")

      assert_equal [@child.id], categories.map { |item| item.fetch("id") }
      assert_equal "Child #{@token}", categories.first.fetch("name")
      assert_equal @parent.id, categories.first.fetch("parent_id")
      assert_equal "Parent #{@token}", categories.first.fetch("parent_name")
    end

    private

    def source_id(suffix)
      "#{@token}-#{suffix}"
    end
  end
end
