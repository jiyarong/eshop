module Erp
  class SuppliersController < BaseController
    include InlineEditableResponse

    SUPPLIER_PAGE_SIZE = 10

    before_action :set_supplier, only: [
      :show, :edit, :update, :attachments, :edit_attachment, :update_attachment,
      :preview_attachment, :download_attachment, :destroy_attachment
    ]
    before_action -> { require_permission!(:manage_purchases) }, except: [ :index, :show, :preview_attachment, :download_attachment ]

    def index
      @q = params[:q].to_s.strip
      @status = params[:status].presence_in(%w[active inactive all]) || "all"
      scope = Ec::Company.tagged("supplier").includes(:developer, :purchaser).order(:name)
      scope = scope.where(is_active: true) if @status == "active"
      scope = scope.where(is_active: false) if @status == "inactive"
      if @q.present?
        keyword = "%#{ActiveRecord::Base.sanitize_sql_like(@q)}%"
        scope = scope.where("name ILIKE :keyword OR origin ILIKE :keyword", keyword: keyword)
      end
      respond_to do |format|
        format.html { @suppliers = paginated_suppliers(scope) }
        format.json { render json: scope }
      end
    end

    def show
      @purchase_orders = @supplier.purchase_orders.order(created_at: :desc)
      @attachments = @supplier.attachments.with_attached_file.order(created_at: :desc)

      respond_to do |format|
        format.html
        format.json { render json: @supplier }
      end
    end

    def new
      @supplier = Ec::Company.new(name: params[:suggested_name], tags: [ "supplier" ], is_active: true)
      load_form_options
      render_modal_or_page(:new, :new_modal)
    end

    def edit
      load_form_options
      render_modal_or_page(:edit, :edit_modal)
    end

    def create
      @supplier = Ec::Company.new(supplier_params)
      @supplier.tags = (Array(@supplier.tags) | [ "supplier" ])
      if @supplier.save
        respond_to do |format|
          format.html do
            if association_create_request?
              render :created_for_association
            else
              redirect_to erp_supplier_path(@supplier), notice: t("erp.suppliers.messages.created")
            end
          end
          format.json { render json: @supplier, status: :created }
        end
      else
        respond_to do |format|
          format.html do
            load_form_options
            render_modal_or_page(:new, :new_modal, status: :unprocessable_entity)
          end
          format.json { render json: { errors: @supplier.errors }, status: :unprocessable_entity }
        end
      end
    end

    def update
      @supplier.assign_attributes(supplier_params)
      @supplier.tags = (Array(@supplier.tags) | [ "supplier" ])
      if @supplier.save
        respond_to do |format|
          format.html { redirect_to erp_supplier_path(@supplier), notice: t("erp.suppliers.messages.updated") }
          format.json { render json: @supplier }
        end
      else
        respond_to do |format|
          format.html do
            load_form_options
            render_modal_or_page(:edit, :edit_modal, status: :unprocessable_entity)
          end
          format.json { render json: { errors: @supplier.errors }, status: :unprocessable_entity }
        end
      end
    end

    def attachments
      uploaded_files = attachment_files_param
      attach_type = attachment_type_param
      unless uploaded_files.present? && Ec::Attachment::COMPANY_ATTACH_TYPES.include?(attach_type)
        redirect_to erp_supplier_path(@supplier), alert: t("erp.suppliers.attachments.upload_failed")
        return
      end

      attachments = []
      blobs = []
      Ec::Attachment.transaction do
        uploaded_files.each do |uploaded_file|
          attachment = build_attachment(uploaded_file, attach_type)
          attachment.save!
          blobs << attachment.attach_file!(io: uploaded_file.tempfile, content_type: uploaded_file.content_type)
          @supplier.attachment_links.create!(ec_attachment: attachment)
          attachments << attachment
        end
      end

      redirect_to erp_supplier_path(@supplier), notice: t("erp.suppliers.attachments.uploaded", count: attachments.size)
    rescue ActiveRecord::RecordInvalid, ActiveStorage::IntegrityError
      blobs.to_a.each(&:purge)
      attachments.to_a.each(&:destroy)
      redirect_to erp_supplier_path(@supplier), alert: t("erp.suppliers.attachments.upload_failed")
    end

    def edit_attachment
      attachment = supplier_attachment
      raise ActionController::BadRequest, "Unsupported inline field" unless params[:inline_field] == "attach_type"

      render partial: "shared/inline_edit_cell",
        locals: attachment_inline_cell_locals(attachment, editing: true)
    end

    def update_attachment
      attachment = supplier_attachment
      raise ActionController::BadRequest, "Unsupported update request" unless inline_edit_request?

      field = inline_field_name(%w[attach_type])
      attach_type = params.require(:ec_attachment).permit(:attach_type)[:attach_type]
      raise ActionController::BadRequest, "Unsupported attachment type" unless attach_type.in?(Ec::Attachment::COMPANY_ATTACH_TYPES)

      if attachment.update(field => attach_type)
        render_inline_edit_success(
          frame_id: view_context.attachment_type_inline_frame_id(attachment, dom_id_prefix: attachment_dom_id_prefix),
          feedback_target: "global_toast",
          cell_partial: "shared/inline_edit_cell",
          cell_locals: attachment_inline_cell_locals(attachment),
          message: t("erp.inline_edit.messages.saved")
        )
      else
        render_inline_edit_failure(
          frame_id: view_context.attachment_type_inline_frame_id(attachment, dom_id_prefix: attachment_dom_id_prefix),
          feedback_target: "global_toast",
          cell_partial: "shared/inline_edit_cell",
          cell_locals: attachment_inline_cell_locals(attachment, editing: true),
          message: t("erp.inline_edit.messages.save_failed")
        )
      end
    end

    def preview_attachment
      attachment = supplier_attachment

      if view_context.attachment_office_previewable?(attachment)
        source_url = attachment.file.url(disposition: :inline, filename: attachment.filename)
        redirect_to "https://view.officeapps.live.com/op/embed.aspx?src=#{CGI.escape(source_url)}", allow_other_host: true
      elsif view_context.attachment_browser_previewable?(attachment)
        if attachment.file.service.is_a?(ActiveStorage::Service::QiniuService)
          redirect_to attachment.file.url(disposition: :inline, filename: attachment.filename), allow_other_host: true
        else
          send_data attachment.file.download,
                    filename: attachment.filename,
                    type: view_context.attachment_browser_preview_content_type(attachment),
                    disposition: "inline"
        end
      else
        head :unprocessable_entity
      end
    end

    def download_attachment
      attachment = supplier_attachment

      if attachment.file.service.is_a?(ActiveStorage::Service::QiniuService)
        redirect_to attachment.file.url(disposition: :attachment, filename: attachment.filename), allow_other_host: true
      else
        send_data attachment.file.download,
                  filename: attachment.filename,
                  type: attachment.file.content_type || "application/octet-stream",
                  disposition: "attachment"
      end
    end

    def destroy_attachment
      attachment = supplier_attachment
      @supplier.attachment_links.find_by!(ec_attachment: attachment).destroy!
      if attachment.attachment_links.reload.none?
        attachment.file.purge if attachment.file.attached?
        attachment.destroy!
      end
      redirect_to erp_supplier_path(@supplier), notice: t("erp.suppliers.attachments.deleted"), status: :see_other
    end

    private

    def paginated_suppliers(scope)
      current_page = supplier_page_param
      suppliers = scope.page(current_page).per(SUPPLIER_PAGE_SIZE)
      if suppliers.total_pages.positive? && current_page > suppliers.total_pages
        suppliers = scope.page(suppliers.total_pages).per(SUPPLIER_PAGE_SIZE)
      end
      suppliers
    end

    def supplier_page_param
      requested_page = params[:jump_page].presence || params[:page].presence
      current_page = params[:current_page].presence || params[:page].presence

      page = requested_page.to_i if requested_page.to_s.match?(/\A\d+\z/)
      page ||= current_page.to_i if current_page.to_s.match?(/\A\d+\z/)
      page = 1 if page.to_i <= 0
      page
    end

    def set_supplier
      @supplier = Ec::Company.tagged("supplier").find(params[:id])
    end

    def load_form_options
      @user_options = User.where(active: true).order(:name, :email)
    end

    def supplier_params
      params.require(:ec_company).permit(
        :name, :origin, :invoice_type, :channel, :online_url,
        :developer_id, :purchaser_id, :factory_audited, :credit_terms,
        :supplier_grade, :supplier_evaluation, :contact_name, :phone,
        :wechat, :address, :is_active, :memo, tags: []
      )
    end

    def association_create_request?
      params[:association_dom_id].present?
    end

    def attachment_files_param
      files = Array(params.dig(:ec_attachment, :files)).compact_blank
      files.presence || Array(params.dig(:ec_attachment, :file)).compact_blank
    end

    def attachment_type_param
      params.dig(:ec_attachment, :attach_type).to_s
    end

    def attachment_type_options
      Ec::Attachment::COMPANY_ATTACH_TYPES.map do |type|
        [I18n.t("erp.suppliers.attachment_types.#{type}"), type]
      end
    end

    def attachment_dom_id_prefix
      "supplier-#{@supplier.id}-attachments"
    end

    def attachment_inline_cell_locals(attachment, editing: false)
      view_context.attachment_type_inline_cell_locals(
        attachment,
        options: attachment_type_options,
        update_path: attachment_erp_supplier_path(@supplier, attachment, locale: params[:locale]),
        edit_path: edit_attachment_erp_supplier_path(@supplier, attachment, locale: params[:locale]),
        dom_id_prefix: attachment_dom_id_prefix,
        editing: editing
      )
    end

    def build_attachment(uploaded_file, attach_type)
      filename = File.basename(uploaded_file.original_filename.to_s)
      filename = "attachment" if filename.blank? || filename == "."
      safe_filename = filename.gsub(/[^\w.\-]+/, "_").presence || "attachment"
      Ec::Attachment.new(
        attach_type: attach_type,
        filename: filename,
        qiniu_hash: uploaded_file_digest(uploaded_file),
        oss_path: "ec/companies/#{@supplier.id}/attachments/#{SecureRandom.uuid}/#{safe_filename}"
      )
    end

    def uploaded_file_digest(uploaded_file)
      uploaded_file.rewind
      Digest::SHA256.hexdigest(uploaded_file.read)
    ensure
      uploaded_file.rewind if uploaded_file.respond_to?(:rewind)
    end

    def supplier_attachment
      @supplier.attachments.with_attached_file.find(params[:attachment_id])
    end
  end
end
