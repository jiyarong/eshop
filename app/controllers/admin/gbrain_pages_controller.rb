module Admin
  class GbrainPagesController < BaseController
    before_action :set_page, only: %i[show edit update destroy remote retry_sync]

    def index
      @source = params[:source] == "remote" ? "remote" : "local"
      if @source == "remote"
        @remote_result = gbrain_client.list_pages(limit: 100)
        @remote_pages = Gbrain::McpResult.pages(@remote_result)
      else
        @pages = GbrainPage.recent_first
      end
    rescue StandardError => error
      @error = error.message
    end

    def show
    end

    def new
      @page = GbrainPage.new
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
      @remote_result = gbrain_client.get_page(@slug)
      @remote_page = Gbrain::McpResult.payload(@remote_result)
      @remote_content = Gbrain::McpResult.page_content(@remote_page)
      @remote_metadata = Gbrain::McpResult.page_metadata(@remote_page)
    rescue StandardError => error
      @error = error.message
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

    def page_params
      permitted = params.require(:gbrain_page).permit(:slug, :content)
      permitted.delete(:slug) if @page.persisted?
      permitted
    end

    def gbrain_client
      @gbrain_client ||= Gbrain::Client.new
    end
  end
end
