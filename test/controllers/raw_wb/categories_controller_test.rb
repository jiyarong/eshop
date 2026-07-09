require "test_helper"
require "securerandom"

class RawWb::CategoriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(4)
    @category = RawWb::Category.create!(wb_id: unique_wb_id(1), name: "WB category #{@token}")
    @subject = RawWb::Subject.create!(wb_id: unique_wb_id(2), name: "WB subject #{@token}", category: @category)
  end

  teardown do
    RawWb::Subject.where(id: @subject&.id).delete_all
    RawWb::Category.where(id: @category&.id).delete_all
  end

  test "tree returns categories with their subjects" do
    get "/raw_wb/categories/tree", headers: { "Accept" => "application/json" }

    assert_response :success
    body = JSON.parse(response.body)
    categories = body.fetch("data").fetch("categories")
    category = categories.find { |item| item.fetch("id") == @category.id }

    assert_equal true, body.fetch("success")
    assert_equal @category.wb_id, category.fetch("wb_id")
    assert_equal @category.name, category.fetch("name")

    subjects = category.fetch("subjects")
    assert_equal 1, subjects.size
    assert_equal @subject.id, subjects.first.fetch("id")
    assert_equal @subject.wb_id, subjects.first.fetch("wb_id")
    assert_equal @subject.name, subjects.first.fetch("name")
  end

  private

  def unique_wb_id(offset)
    @token.hex % 1_000_000 + offset
  end
end
