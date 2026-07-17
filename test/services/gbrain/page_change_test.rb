require "test_helper"

class Gbrain::PageChangeTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @token = SecureRandom.hex(6)
  end

  teardown do
    clear_enqueued_jobs
    GbrainPage.where("slug LIKE ?", "change-#{@token}%").delete_all
  end

  test "does not queue another write when content did not change" do
    page = create_page(sync_status: "synced", knowledge_base_written_at: Time.current)

    assert_no_enqueued_jobs do
      assert Gbrain::PageChange.save(page, content: page.content)
    end

    assert_equal "synced", page.reload.sync_status
  end

  test "retry preserves whether the pending operation is a deletion" do
    page = create_page(delete_requested_at: Time.current, sync_status: "failed", last_error: "failed")

    assert_enqueued_with(job: Gbrain::PageSyncJob, queue: "gbrain") do
      Gbrain::PageChange.retry(page)
    end

    assert_equal "pending_delete", page.reload.sync_status
    assert_nil page.last_error
  end

  private

  def create_page(attributes = {})
    GbrainPage.create!({
      slug: "change-#{@token}-#{SecureRandom.hex(2)}",
      content: "body",
      content_updated_at: Time.current
    }.merge(attributes))
  end
end
