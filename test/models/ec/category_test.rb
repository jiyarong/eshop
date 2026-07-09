require "test_helper"

class Ec::CategoryTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(6)
  end

  teardown do
    Ec::Category.where(source: "test", source_id: source_ids).delete_all if defined?(Ec::Category)
  end

  test "supports source identity and parent categories" do
    parent = Ec::Category.create!(
      source: "test",
      source_type: "category",
      source_id: source_id("parent"),
      origin_name: "Родитель",
      origin_language: "ru",
      name_ru: "Родитель"
    )
    child = Ec::Category.create!(
      source: "test",
      source_type: "subject",
      source_id: source_id("child"),
      parent: parent,
      origin_name: "Дочерняя",
      origin_language: "ru",
      name_ru: "Дочерняя"
    )

    assert_equal parent, child.parent
    assert_equal [child], parent.children.to_a
  end

  test "requires unique source identity" do
    Ec::Category.create!(
      source: "test",
      source_type: "category",
      source_id: source_id("duplicate"),
      origin_name: "Категория",
      origin_language: "ru",
      name_ru: "Категория"
    )

    duplicate = Ec::Category.new(
      source: "test",
      source_type: "category",
      source_id: source_id("duplicate"),
      origin_name: "Категория",
      origin_language: "ru",
      name_ru: "Категория"
    )

    assert_not duplicate.valid?
    assert duplicate.errors[:source_id].any?
  end

  private

  def source_id(suffix)
    "#{@token}-#{suffix}"
  end

  def source_ids
    %w[parent child duplicate].map { |suffix| source_id(suffix) }
  end
end
