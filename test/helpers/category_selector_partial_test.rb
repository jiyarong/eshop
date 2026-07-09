require "test_helper"

class CategorySelectorPartialTest < ActionView::TestCase
  setup do
    @token = SecureRandom.hex(4)
    @parent = Ec::Category.create!(
      source: "test",
      source_type: "category",
      source_id: source_id("parent"),
      origin_name: "Parent #{@token}",
      origin_language: "en",
      name_en: "Parent #{@token}"
    )
    @child = Ec::Category.create!(
      source: "test",
      source_type: "subject",
      source_id: source_id("child"),
      parent: @parent,
      origin_name: "Child #{@token}",
      origin_language: "en",
      name_en: "Child #{@token}"
    )
  end

  teardown do
    Ec::Category.where(source: "test", source_id: [source_id("parent"), source_id("child")]).delete_all
  end

  test "allows a top-level category to be the submitted category" do
    render partial: "shared/category_selector", locals: { field_name: "category_id", selected_category_id: @parent.id }

    assert_select ".category-selector[data-action='click->category-selector#stopClick']"
    assert_select "input[type='hidden'][name='category_id'][value=?]", @parent.id.to_s
    assert_select "button.category-selector__trigger span", "Parent #{@token}"
    assert_select ".category-selector__search input[type='search']"
    assert_select ".category-selector__cancel"
    assert_select ".category-selector__list[data-category-selector-target='parentList'] button[data-category-id=?][aria-selected='true']", @parent.id.to_s
    assert_select ".category-selector__list[data-category-selector-target='childList'] button[data-category-id=?][aria-selected='true']", @child.id.to_s, count: 0
  end

  private

  def source_id(suffix)
    "#{@token}-#{suffix}"
  end
end
