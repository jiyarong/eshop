require "test_helper"

class GbrainPageTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(6)
  end

  teardown do
    GbrainPage.where("slug LIKE ?", "test-#{@token}%").delete_all
  end

  test "requires a unique slug and content update time" do
    page = GbrainPage.new(slug: "test-#{@token}", content: "body")

    assert_not page.valid?
    assert page.errors[:content_updated_at].present?
  end

  test "does not allow a persisted slug to change" do
    page = create_page

    page.slug = "test-#{@token}-changed"

    assert_not page.valid?
    assert page.errors[:slug].present?
  end

  private

  def create_page
    GbrainPage.create!(
      slug: "test-#{@token}",
      content: "body",
      content_updated_at: Time.current
    )
  end
end
