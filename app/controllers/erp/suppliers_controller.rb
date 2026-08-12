module Erp
  class SuppliersController < BaseController
    before_action :set_supplier, only: [ :show, :edit, :update, :attachments, :download_attachment, :destroy_attachment ]
    before_action -> { require_permission!(:manage_purchases) }, except: [ :index, :show, :download_attachment ]

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
      @suppliers = scope

      respond_to do |format|
        format.html
        format.json { render json: @suppliers }
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
      uploaded_file = params.dig(:ec_attachment, :file)
      attach_type = params.dig(:ec_attachment, :attach_type).to_s
      unless uploaded_file.present? && Ec::Attachment::COMPANY_ATTACH_TYPES.include?(attach_type)
        redirect_to erp_supplier_path(@supplier), alert: t("erp.suppliers.attachments.upload_failed")
        return
      end

      attachment = build_attachment(uploaded_file, attach_type)
      attachment.save!
      attachment.attach_file!(io: uploaded_file.tempfile, content_type: uploaded_file.content_type)
      @supplier.attachment_links.create!(ec_attachment: attachment)
      redirect_to erp_supplier_path(@supplier), notice: t("erp.suppliers.attachments.uploaded")
    rescue ActiveRecord::RecordInvalid, ActiveStorage::IntegrityError
      attachment&.file&.purge if attachment&.file&.attached?
      attachment&.destroy
      redirect_to erp_supplier_path(@supplier), alert: t("erp.suppliers.attachments.upload_failed")
    end

    def download_attachment
      attachment = supplier_attachment
      redirect_to rails_blob_path(attachment.file, disposition: "attachment")
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

    def build_attachment(uploaded_file, attach_type)
      filename = File.basename(uploaded_file.original_filename.to_s).presence || "attachment"
      uploaded_file.rewind
      digest = Digest::SHA256.hexdigest(uploaded_file.read)
      uploaded_file.rewind
      safe_filename = filename.gsub(/[^\w.\-]+/, "_").presence || "attachment"
      Ec::Attachment.new(
        attach_type: attach_type,
        filename: filename,
        qiniu_hash: digest,
        oss_path: "ec/companies/#{@supplier.id}/attachments/#{SecureRandom.uuid}/#{safe_filename}"
      )
    end

    def supplier_attachment
      @supplier.attachments.with_attached_file.find(params[:attachment_id])
    end
  end
end
