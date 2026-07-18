require "test_helper"

class GbrainPageTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(6)
  end

  teardown do
    GbrainPage.where("slug LIKE ?", "%test-#{@token}%").delete_all
  end

  test "requires a unique slug and content update time" do
    page = GbrainPage.new(slug: "notes/test-#{@token}", content: "body")

    assert_not page.valid?
    assert page.errors[:content_updated_at].present?
  end

  test "does not allow a persisted slug to change" do
    page = create_page

    page.slug = "notes/test-#{@token}-changed"

    assert_not page.valid?
    assert page.errors[:slug].present?
  end

  test "requires type-specific scopes and slug prefixes" do
    page = GbrainPage.new(gbrain_page_attributes(
      slug: "notes/test-#{@token}-region",
      page_type: "region-profile",
      region_scope: []
    ))

    assert_not page.valid?
    assert page.errors[:slug].present?
    assert page.errors[:region_scope].present?
  end

  test "policy requires an effective date" do
    page = GbrainPage.new(gbrain_page_attributes(
      slug: "policies/test-#{@token}",
      page_type: "policy",
      effective_date: nil
    ))

    assert_not page.valid?
    assert page.errors[:effective_date].present?
  end

  test "compiles structured fields into gbrain frontmatter and markdown" do
    page = GbrainPage.new(gbrain_page_attributes(
      slug: "notes/test-#{@token}-compiled",
      title: "Siberia warehouse strategy",
      aliases: [ "Сибирь FBO" ],
      summary: "Prefer regional FBO for stable demand."
    ))

    compiled = page.compiled_content
    metadata = YAML.safe_load(compiled.split("---\n", 3).second)

    assert_equal "Siberia warehouse strategy", metadata["title"]
    assert_equal "note", metadata["type"]
    assert_equal [ "Сибирь FBO" ], metadata["aliases"]
    assert_includes compiled, "# Siberia warehouse strategy"
    assert_includes compiled, "> Prefer regional FBO for stable demand."
  end

  test "allows an existing legacy page to change sync state without wiki fields" do
    page = GbrainPage.create!(gbrain_page_attributes(slug: "notes/test-#{@token}-legacy"))
    page.update_columns(
      title: nil, page_type: nil, subtype: nil, aliases: [], tags: [], platform: nil,
      country: nil, reviewed_at: nil, review_after: nil, source_tier: nil,
      confidence: nil, summary: nil
    )

    assert page.update(sync_status: "failed")
  end

  private

  def create_page
    GbrainPage.create!(gbrain_page_attributes(slug: "notes/test-#{@token}"))
  end
end
