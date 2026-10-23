module Admin
  class GbrainPagesController < BaseController
    REMOTE_LIST_LIMIT = 100
    PAGE_SIZE = 20

    before_action :set_page, only: %i[show edit update destroy remote retry_sync]
    before_action :set_list_filters, only: %i[index remote_page destroy_remote]

    def index
      @source = params[:source] == "remote" ? "remote" : "local"
      if @source == "remote"
        load_remote_pages
      else
        load_local_pages
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

    def classify
      attributes = page_classifier.classify(params[:content])
      render json: { page: attributes }
    rescue Gbrain::PageClassifier::InvalidInput
      render json: { error: t("admin.gbrain.classifier.errors.blank") }, status: :unprocessable_entity
    rescue Gbrain::PageClassifier::InvalidResponse
      render json: { error: t("admin.gbrain.classifier.errors.invalid_response") }, status: :unprocessable_entity
    rescue Gbrain::PageClassifier::ProviderError
      render json: { error: t("admin.gbrain.classifier.errors.unavailable") }, status: :bad_gateway
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
      redirect_to admin_gbrain_pages_path(@list_filters.merge(source: "remote", page: params[:page])), notice: t("admin.gbrain.notices.remote_deleted")
    rescue StandardError => error
      redirect_to admin_gbrain_pages_path(@list_filters.merge(source: "remote", page: params[:page])), alert: error.message
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
      remote_pages.select! { |page| page["type"] == @page_type } if @page_type
      if @query.present?
        keyword = @query.downcase
        remote_pages.select! { |page| %w[title slug].any? { |field| page[field].to_s.downcase.include?(keyword) } }
      end
      set_pagination(remote_pages.size)
      @remote_pages = remote_pages.slice((@page_number - 1) * PAGE_SIZE, PAGE_SIZE) || []
    end

    def load_local_pages
      scope = GbrainPage.recent_first
      scope = scope.where(page_type: @page_type) if @page_type
      scope = scope.where(sync_status: @sync_status) if @sync_status
      if @query.present?
        keyword = "%#{GbrainPage.sanitize_sql_like(@query)}%"
        scope = scope.where("slug ILIKE :keyword OR title ILIKE :keyword OR summary ILIKE :keyword", keyword: keyword)
      end
      set_pagination(scope.count)
      @pages = scope.limit(PAGE_SIZE).offset((@page_number - 1) * PAGE_SIZE)
        .select(:id, :slug, :page_type, :sync_status, :content_updated_at, :knowledge_base_written_at, :delete_requested_at)
    end

    def set_list_filters
      @query = params[:q].to_s.strip
      @page_type = params[:page_type].presence_in(GbrainPage::PAGE_TYPES.keys)
      @sync_status = params[:sync_status].presence_in(GbrainPage::SYNC_STATUSES)
      @list_filters = { q: @query.presence, page_type: @page_type, sync_status: @sync_status, locale: params[:locale].presence }.compact
    end

    def set_pagination(total)
      @total = total
      @page_count = [ (total.to_f / PAGE_SIZE).ceil, 1 ].max
      requested_page = if params.key?(:jump_page)
        Integer(params[:jump_page], exception: false) || params[:current_page].to_i
      else
        params[:page].to_i
      end
      @page_number = requested_page.clamp(1, @page_count)
      @from = total.zero? ? 0 : ((@page_number - 1) * PAGE_SIZE) + 1
      @to = [ @page_number * PAGE_SIZE, total ].min
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

    def page_classifier
      @page_classifier ||= Gbrain::PageClassifier.new
    end
  end
end
