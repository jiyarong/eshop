require "test_helper"

class Admin::GbrainPagesControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  class FakeClient
    attr_reader :calls

    def initialize
      @calls = []
    end

    def list_pages(limit:)
      calls << [ "list_pages", limit ]
      pages = [ {
        "slug" => "remote/page",
        "title" => "Remote Page",
        "type" => "concept",
        "updated_at" => "2026-07-17T08:15:53.690Z"
      } ]
      { "content" => [ { "type" => "text", "text" => JSON.generate(pages) } ] }
    end

    def get_page(slug)
      calls << [ "get_page", slug ]
      page = { "slug" => slug, "title" => "Remote Page", "compiled_truth" => "# Remote body" }
      { "content" => [ { "type" => "text", "text" => JSON.generate(page) } ] }
    end

    def query(text, limit:)
      calls << [ "query", text, limit ]
      { "results" => [ { "slug" => "query/result" } ] }
    end

    def search(text, limit:)
      calls << [ "search", text, limit ]
      { "results" => [ { "slug" => "search/result" } ] }
    end
  end

  setup do
    @token = SecureRandom.hex(6)
    @admin = create_user_with_roles("gbrain-admin-#{@token}@example.com", "super_admin")
    @viewer = create_user_with_roles("gbrain-viewer-#{@token}@example.com", "auditor")
    @page = create_page
  end

  teardown do
    clear_enqueued_jobs
    GbrainPage.where("slug LIKE ?", "admin-#{@token}%").delete_all
    UserRole.joins(:user).where("users.email LIKE ?", "%gbrain-%#{@token}%").delete_all
    User.where("email LIKE ?", "%gbrain-%#{@token}%").delete_all
  end

  test "admin can list local pages and see sync timestamps" do
    sign_in @admin

    get admin_gbrain_pages_path, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", "gbrain 知识库"
    assert_select "a", text: @page.slug
    assert_select ".status-pill", text: /等待写入/
    assert_select "th", text: "内容更新时间"
    assert_select "th", text: "知识库写入时间"
  end

  test "non admin cannot access knowledge base management" do
    sign_in @viewer

    get admin_gbrain_pages_path, headers: { "Accept" => "text/html" }

    assert_response :forbidden
  end

  test "admin can open the new and edit forms" do
    sign_in @admin
    get admin_new_gbrain_page_path, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "input[name='gbrain_page[slug]']:not([readonly])"
    assert_select "textarea[name='gbrain_page[content]']"

    sign_in @admin
    get admin_edit_gbrain_page_path(@page), headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "input[name='gbrain_page[slug]'][readonly]"
    assert_select "textarea[name='gbrain_page[content]']", text: @page.content
  end

  test "creating a page saves locally and queues a write" do
    sign_in @admin

    assert_difference("GbrainPage.count", 1) do
      assert_enqueued_with(job: Gbrain::PageSyncJob, queue: "gbrain") do
        post admin_gbrain_pages_path, params: {
          gbrain_page: {
            slug: "admin-#{@token}-new",
            content: "---\ntype: note\n---\n# New"
          }
        }
      end
    end

    page = GbrainPage.find_by!(slug: "admin-#{@token}-new")
    assert_equal "pending", page.sync_status
    assert_not_nil page.content_updated_at
    assert_nil page.knowledge_base_written_at
    assert_redirected_to admin_gbrain_page_path(page)
  end

  test "updating content records a new content time and queues a write" do
    sign_in @admin
    old_time = @page.content_updated_at

    travel 1.minute do
      assert_enqueued_with(job: Gbrain::PageSyncJob, queue: "gbrain") do
        patch admin_gbrain_page_path(@page), params: {
          gbrain_page: { slug: "ignored-change", content: "updated body" }
        }
      end
    end

    @page.reload
    assert_equal "updated body", @page.content
    assert_equal "pending", @page.sync_status
    assert_operator @page.content_updated_at, :>, old_time
    assert_equal "admin-#{@token}", @page.slug
  end

  test "deleting a page keeps it locally until the queued delete succeeds" do
    sign_in @admin

    assert_no_difference("GbrainPage.count") do
      assert_enqueued_with(job: Gbrain::PageSyncJob, queue: "gbrain") do
        delete admin_gbrain_page_path(@page)
      end
    end

    @page.reload
    assert_equal "pending_delete", @page.sync_status
    assert_not_nil @page.delete_requested_at
  end

  test "admin can list remote pages" do
    sign_in @admin
    client = FakeClient.new

    with_gbrain_client(client) do
      get admin_gbrain_pages_path(source: "remote"), headers: { "Accept" => "text/html" }
      assert_response :success
      assert_select "details.gbrain-remote-item", count: 1
      assert_select ".gbrain-remote-item__summary", /Remote Page/
      assert_select ".gbrain-remote-item__summary", /remote\/page/
      assert_select "a[href=?]", remote_page_admin_gbrain_pages_path(slug: "remote/page"), text: /Get 查看/
    end

    assert_equal [ [ "list_pages", 100 ] ], client.calls
  end

  test "admin can read a remote page" do
    sign_in @admin
    client = FakeClient.new

    with_gbrain_client(client) do
      get remote_admin_gbrain_page_path(@page), headers: { "Accept" => "text/html" }
      assert_response :success
      assert_select ".gbrain-result", /Remote body/
    end

    assert_equal [ [ "get_page", @page.slug ] ], client.calls
  end

  test "admin can get a remote page that has no local record" do
    sign_in @admin
    client = FakeClient.new

    with_gbrain_client(client) do
      get remote_page_admin_gbrain_pages_path(slug: "remote/only"), headers: { "Accept" => "text/html" }
      assert_response :success
      assert_select "h1", "remote/only"
      assert_select "[data-controller='markdown']"
      assert_select "[data-markdown-target='source']", /# Remote body/
      assert_select "article.gbrain-markdown[data-markdown-target='output'][hidden]"
      assert_select ".gbrain-metadata", /Remote Page/
      assert_select ".gbrain-metadata", text: /compiled_truth/, count: 0
    end

    assert_equal [ [ "get_page", "remote/only" ] ], client.calls
  end

  test "admin can validate a query" do
    sign_in @admin
    client = FakeClient.new

    with_gbrain_client(client) do
      get validation_admin_gbrain_pages_path, params: { mode: "query", query: "库存", limit: 5 }, headers: { "Accept" => "text/html" }
      assert_response :success
      assert_select ".gbrain-result", /query\/result/
    end

    assert_equal [ [ "query", "库存", 5 ] ], client.calls
  end

  test "admin can validate a keyword search" do
    sign_in @admin
    client = FakeClient.new

    with_gbrain_client(client) do
      get validation_admin_gbrain_pages_path, params: { mode: "search", query: "利润", limit: 8 }, headers: { "Accept" => "text/html" }
      assert_response :success
      assert_select ".gbrain-result", /search\/result/
    end

    assert_equal [ [ "search", "利润", 8 ] ], client.calls
  end

  private

  def with_gbrain_client(client)
    singleton_class = Gbrain::Client.singleton_class
    singleton_class.define_method(:new) { |**| client }
    yield
  ensure
    singleton_class.remove_method(:new)
  end

  def create_page
    GbrainPage.create!(
      slug: "admin-#{@token}",
      content: "body",
      content_updated_at: Time.current
    )
  end
end
