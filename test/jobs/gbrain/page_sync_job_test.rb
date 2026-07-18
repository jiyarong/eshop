require "test_helper"

class Gbrain::PageSyncJobTest < ActiveJob::TestCase
  class FakeClient
    attr_reader :calls

    def initialize(error: nil, on_put: nil)
      @error = error
      @on_put = on_put
      @calls = []
    end

    def put_page(slug:, content:)
      calls << [ "put_page", slug, content ]
      @on_put&.call
      raise @error if @error
    end

    def delete_page(slug)
      calls << [ "delete_page", slug ]
      raise @error if @error
    end
  end

  setup do
    @token = SecureRandom.hex(6)
  end

  teardown do
    GbrainPage.where("slug LIKE ?", "%job-#{@token}%").delete_all
  end

  test "writes the page and records the knowledge base write time" do
    page = create_page
    client = FakeClient.new

    perform_job(page, client)

    page.reload
    assert_equal [ [ "put_page", page.slug, page.compiled_content ] ], client.calls
    assert_equal "synced", page.sync_status
    assert_not_nil page.knowledge_base_written_at
  end

  test "does not mark newer content as synced after an older write finishes" do
    page = create_page
    newer_time = 1.minute.from_now
    client = FakeClient.new(on_put: -> {
      page.update_columns(content: "new body", content_updated_at: newer_time, sync_status: "pending")
    })

    perform_job(page, client)

    page.reload
    assert_equal "pending", page.sync_status
    assert_equal "new body", page.content
  end

  test "deletes the local record after gbrain confirms deletion" do
    page = create_page(delete_requested_at: Time.current, sync_status: "pending_delete")
    client = FakeClient.new

    perform_job(page, client)

    assert_equal [ [ "delete_page", page.slug ] ], client.calls
    assert_not GbrainPage.exists?(page.id)
  end

  test "records the error and keeps the page for retry" do
    page = create_page
    client = FakeClient.new(error: Gbrain::Client::Error.new("network failed"))

    assert_raises(Gbrain::Client::Error) { perform_job(page, client) }

    page.reload
    assert_equal "failed", page.sync_status
    assert_equal "network failed", page.last_error
  end

  test "skips a duplicate job after the page is already synced" do
    page = create_page(sync_status: "synced", knowledge_base_written_at: Time.current)
    client = FakeClient.new

    perform_job(page, client)

    assert_empty client.calls
  end

  private

  def perform_job(page, client)
    job = Gbrain::PageSyncJob.new(page.id)
    job.define_singleton_method(:client) { client }
    job.perform_now
  end

  def create_page(attributes = {})
    GbrainPage.create!(gbrain_page_attributes(
      slug: "notes/job-#{@token}-#{SecureRandom.hex(2)}",
      content: "old body",
      **attributes
    ))
  end
end
