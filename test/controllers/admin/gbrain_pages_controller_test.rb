require "test_helper"

class Admin::GbrainPagesControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  class FakeClient
    attr_reader :calls

    def initialize(pages: nil, delete_error: nil)
      @calls = []
      @pages = pages || [ {
        "slug" => "remote/page",
        "title" => "Remote Page",
        "type" => "concept",
        "updated_at" => "2026-07-17T08:15:53.690Z"
      } ]
      @delete_error = delete_error
    end

    def list_pages(limit:)
      calls << [ "list_pages", limit ]
      { "content" => [ { "type" => "text", "text" => JSON.generate(@pages) } ] }
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

    def delete_page(slug)
      calls << [ "delete_page", slug ]
      raise Gbrain::Client::Error, @delete_error if @delete_error

      { "status" => "soft_deleted", "slug" => slug }
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
      assert_select "table.gbrain-remote-pages-table"
      assert_select "table.gbrain-remote-pages-table th", "标题"
      assert_select "table.gbrain-remote-pages-table tbody tr", count: 1
      assert_select ".gbrain-remote-title", "Remote Page"
      assert_select ".gbrain-remote-slug", /remote\/page/
      assert_select "a[href=?]", remote_page_admin_gbrain_pages_path(slug: "remote/page", page: 1), text: /Get 查看/
      assert_select "form[action=?][method=post][data-turbo-confirm]", destroy_remote_page_admin_gbrain_pages_path do
        assert_select "input[name=_method][value=delete]"
        assert_select "input[name=slug][value='remote/page']"
      end
    end

    assert_equal [ [ "list_pages", 100 ] ], client.calls
  end

  test "admin can paginate the remote result set" do
    sign_in @admin
    pages = 45.times.map do |index|
      {
        "slug" => format("remote/page-%02d", index + 1),
        "title" => format("Remote Page %02d", index + 1),
        "type" => "concept",
        "updated_at" => "2026-07-17T08:15:53.690Z"
      }
    end
    client = FakeClient.new(pages: pages)

    with_gbrain_client(client) do
      get admin_gbrain_pages_path(source: "remote", page: 2), headers: { "Accept" => "text/html" }
      assert_response :success
      assert_select "table.gbrain-remote-pages-table tbody tr", count: 20
      assert_select ".gbrain-remote-title", /Remote Page 21/
      assert_select ".gbrain-remote-title", /Remote Page 40/
      assert_select ".gbrain-remote-title", text: /Remote Page 20/, count: 0
      assert_select ".gbrain-remote-count", "显示第 21-40 条，共 45 条"
      assert_select ".gbrain-remote-pagination__page[aria-current=page]", "2"
      assert_select "a[href=?]", admin_gbrain_pages_path(source: "remote", page: 1), text: /上一页/
      assert_select "a[href=?]", admin_gbrain_pages_path(source: "remote", page: 3), text: /下一页/
    end

    assert_equal [ [ "list_pages", 100 ] ], client.calls
  end

  test "remote list renders an empty table row when no pages are returned" do
    sign_in @admin
    client = FakeClient.new(pages: [])

    with_gbrain_client(client) do
      get admin_gbrain_pages_path(source: "remote"), headers: { "Accept" => "text/html" }
      assert_response :success
      assert_select "table.gbrain-remote-pages-table tbody tr", count: 1
      assert_select "table.gbrain-remote-pages-table td.empty-state[colspan='5']", "list_pages 没有返回可展示的文档。"
      assert_select ".gbrain-remote-pagination", count: 0
    end
  end

  test "remote pagination clamps a page beyond the available result set" do
    sign_in @admin
    pages = 21.times.map { |index| { "slug" => "remote/page-#{index + 1}", "title" => "Remote Page #{index + 1}" } }
    client = FakeClient.new(pages: pages)

    with_gbrain_client(client) do
      get admin_gbrain_pages_path(source: "remote", page: 99), headers: { "Accept" => "text/html" }
      assert_response :success
      assert_select "table.gbrain-remote-pages-table tbody tr", count: 1
      assert_select ".gbrain-remote-count", "显示第 21-21 条，共 21 条"
      assert_select ".gbrain-remote-pagination__page[aria-current=page]", "2"
    end
  end

  test "admin can delete a remote page and return to the same list page" do
    sign_in @admin
    client = FakeClient.new

    with_gbrain_client(client) do
      delete destroy_remote_page_admin_gbrain_pages_path, params: { slug: "remote/page", page: 2 }
      assert_redirected_to admin_gbrain_pages_path(source: "remote", page: 2)
      assert_equal "远端文档已从 gbrain 列表删除。", flash[:notice]
    end

    assert_equal [ [ "delete_page", "remote/page" ] ], client.calls
  end

  test "remote delete failure returns the MCP error to the remote list" do
    sign_in @admin
    client = FakeClient.new(delete_error: "delete rejected")

    with_gbrain_client(client) do
      delete destroy_remote_page_admin_gbrain_pages_path, params: { slug: "remote/page", page: 2 }
      assert_redirected_to admin_gbrain_pages_path(source: "remote", page: 2)
      assert_equal "delete rejected", flash[:alert]
    end
  end

  test "non admin cannot delete a remote page" do
    sign_in @viewer
    client = FakeClient.new

    with_gbrain_client(client) do
      delete destroy_remote_page_admin_gbrain_pages_path, params: { slug: "remote/page" }
      assert_response :forbidden
    end

    assert_empty client.calls
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
      get remote_page_admin_gbrain_pages_path(slug: "remote/only", page: 3), headers: { "Accept" => "text/html" }
      assert_response :success
      assert_select "h1", "remote/only"
      assert_select "[data-controller='markdown']"
      assert_select "[data-markdown-target='source']", /# Remote body/
      assert_select "article.gbrain-markdown[data-markdown-target='output'][hidden]"
      assert_select ".gbrain-metadata", /Remote Page/
      assert_select ".gbrain-metadata", text: /compiled_truth/, count: 0
      assert_select "a[href=?]", admin_gbrain_pages_path(source: "remote", page: 3), text: /返回远端列表/
      assert_select "form[action=?] input[name=page][value='3']", destroy_remote_page_admin_gbrain_pages_path
    end

    assert_equal [ [ "get_page", "remote/only" ] ], client.calls
  end

  test "admin can validate a query" do
    sign_in @admin
    client = FakeClient.new

    with_gbrain_client(client) do
      get validation_admin_gbrain_pages_path, params: { mode: "query", query: "库存", limit: 5 }, headers: { "Accept" => "text/html" }
      assert_response :success
      assert_select "[data-controller='markdown']"
      assert_select "[data-markdown-target='source']", /```json\n.*query\/result.*\n```/m
      assert_select "article.gbrain-validation-result[data-markdown-target='output'][hidden]"
    end

    assert_equal [ [ "query", "库存", 5 ] ], client.calls
  end

  test "admin can validate a keyword search" do
    sign_in @admin
    client = FakeClient.new

    with_gbrain_client(client) do
      get validation_admin_gbrain_pages_path, params: { mode: "search", query: "利润", limit: 8 }, headers: { "Accept" => "text/html" }
      assert_response :success
      assert_select "[data-controller='markdown']"
      assert_select "[data-markdown-target='source']", /```json\n.*search\/result.*\n```/m
      assert_select "article.gbrain-validation-result[data-markdown-target='output'][hidden]"
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
