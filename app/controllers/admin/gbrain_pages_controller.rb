module Admin
  class GbrainPagesController < BaseController
    REMOTE_LIST_LIMIT = 100
    REMOTE_PAGE_SIZE = 20

    before_action :set_page, only: %i[show edit update destroy remote retry_sync]

    def index
      @source = params[:source] == "remote" ? "remote" : "local"
      if @source == "remote"
        load_remote_pages
      else
        @pages = GbrainPage.recent_first
        @pages = @pages.where(page_type: params[:page_type]) if GbrainPage::PAGE_TYPES.key?(params[:page_type])
      end
    rescue StandardError => error
      @error = error.message
    end

    def show
    end

    def new
      @page = GbrainPage.new(
        page_type: "operation-playbook",
        platform: "ozon",
        country: "RU",
        tags: %w[platform/ozon country/ru status/current],
        reviewed_at: Date.current,
        review_after: 3.months.from_now.to_date,
        confidence: "medium"
      )
    end

    def edit
    end

    def create
      @page = GbrainPage.new
      if Gbrain::PageChange.save(@page, page_params)
        redirect_to admin_gbrain_page_path(@page), notice: t("admin.gbrain.notices.queued")
      else
        render :new, status: :unprocessable_entity
      end
    end

    def update
      if Gbrain::PageChange.save(@page, page_params)
        redirect_to admin_gbrain_page_path(@page), notice: t("admin.gbrain.notices.queued")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      Gbrain::PageChange.request_deletion(@page)
      redirect_to admin_gbrain_pages_path, notice: t("admin.gbrain.notices.deletion_queued")
    end

    def retry_sync
      Gbrain::PageChange.retry(@page)
      redirect_to admin_gbrain_page_path(@page), notice: t("admin.gbrain.notices.retry_queued")
    end

    def remote
      @remote_result = gbrain_client.get_page(@page.slug)
      render :show
    rescue StandardError => error
      @error = error.message
      render :show, status: :unprocessable_entity
    end

    def remote_page
      @slug = params[:slug].to_s
      @return_page = [ params[:page].to_i, 1 ].max
      @remote_result = gbrain_client.get_page(@slug)
      @remote_page = Gbrain::McpResult.payload(@remote_result)
      @remote_content = Gbrain::McpResult.page_content(@remote_page)
      @remote_metadata = Gbrain::McpResult.page_metadata(@remote_page)
    rescue StandardError => error
      @error = error.message
    end

    def destroy_remote
      gbrain_client.delete_page(params.require(:slug))
      redirect_to admin_gbrain_pages_path(source: "remote", page: params[:page]), notice: t("admin.gbrain.notices.remote_deleted")
    rescue StandardError => error
      redirect_to admin_gbrain_pages_path(source: "remote", page: params[:page]), alert: error.message
    end

    def validation
      @mode = params[:mode] == "search" ? "search" : "query"
      @query_text = params[:query].to_s
      @limit = params[:limit].to_i.clamp(1, 50)
      @limit = 20 if params[:limit].blank?
      return if @query_text.blank?

      @result = if @mode == "search"
        gbrain_client.search(@query_text, limit: @limit)
      else
        gbrain_client.query(@query_text, limit: @limit)
      end
    rescue StandardError => error
      @error = error.message
    end

    private

    def set_page
      @page = GbrainPage.find(params[:id])
    end

    def load_remote_pages
      @remote_result = gbrain_client.list_pages(limit: REMOTE_LIST_LIMIT)
      remote_pages = Gbrain::McpResult.pages(@remote_result)
      @remote_total = remote_pages.size
      @remote_page_count = [ (@remote_total.to_f / REMOTE_PAGE_SIZE).ceil, 1 ].max
      @remote_page = params[:page].to_i.clamp(1, @remote_page_count)
      @remote_pages = remote_pages.slice((@remote_page - 1) * REMOTE_PAGE_SIZE, REMOTE_PAGE_SIZE) || []
      @remote_from = @remote_total.zero? ? 0 : ((@remote_page - 1) * REMOTE_PAGE_SIZE) + 1
      @remote_to = [ @remote_page * REMOTE_PAGE_SIZE, @remote_total ].min
    end

    def page_params
      permitted = params.require(:gbrain_page).permit(
        :slug, :title, :page_type, :subtype, :aliases_text, :tags_text,
        :platform, :country, :region_scope_text, :category_scope_text,
        :effective_date, :reviewed_at, :review_after, :source_tier,
        :confidence, :summary, :content
      )
      permitted.delete(:slug) if @page.persisted?
      permitted
    end

    def gbrain_client
      @gbrain_client ||= Gbrain::Client.new
    end
  end
end
