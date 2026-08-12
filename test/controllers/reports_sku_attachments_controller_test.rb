require "test_helper"

class ReportsSkuAttachmentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(4).upcase
    @current_user = create_user_with_roles("sku-attachments-#{@token.downcase}@example.com", "manager")
    sign_in @current_user
    @sku = Ec::Sku.create!(
      sku_code: "ATTACH-#{@token}",
      product_name: "附件测试 SKU",
      is_active: true
    )
  end

  teardown do
    attachment_ids = attachments_for_token.pluck(:id)
    attachments_for_token.find_each do |attachment|
      attachment.file.purge if attachment.file.attached?
      attachment.destroy
    end
    Ec::OperationLog.where(record_type: "Ec::Attachment", record_id: attachment_ids).delete_all
    Ec::AttachmentLink.where(attachable_type: "Ec::Sku", attachable_id: @sku&.id).delete_all
    Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
    UserRole.joins(:user).where("users.email LIKE ?", "sku-attachments-#{@token.downcase}%").delete_all
    User.where("email LIKE ?", "sku-attachments-#{@token.downcase}%").delete_all
  end

  test "sku detail renders attachments at the bottom of basic configuration" do
    sign_in @current_user
    get report_sku_path(@sku.sku_code, tab: "basic"), headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select ".sku-detail-tabs__link", text: "附件", count: 0
    assert_select ".sku-detail-tabs__link[aria-current='page']", text: "基础配置"
    assert_select "form[action=?]", report_sku_attachments_path(@sku.sku_code)
    assert_select "button", text: /上传附件/
    assert_select "dialog.attachment-dialog"
    assert_select "input[type='file'][name='ec_attachment[files][]'][multiple]"
    assert_select ".attachment-dropzone", text: /点击或将文件拖到此区域/
    assert_select "#sku-#{@sku.id}-attachments-upload-dialog"
    assert_select "td.empty-state", text: "暂无附件"
  end

  test "uploads and links multiple attachments to sku" do
    assert_difference -> { Ec::Attachment.count }, 2 do
      assert_difference -> { Ec::AttachmentLink.where(attachable: @sku).count }, 2 do
        post report_sku_attachments_path(@sku.sku_code),
             params: {
               ec_attachment: {
                 attach_type: "unknown",
                 files: [
                   uploaded_file("first body #{@token}", filename: "first-#{@token}.txt"),
                   uploaded_file("second body #{@token}", filename: "second-#{@token}.pdf", content_type: "application/pdf")
                 ]
               }
             },
             headers: { "Accept" => "text/html" }
      end
    end

    assert_redirected_to report_sku_path(@sku.sku_code, tab: "basic")
    attachments = @sku.attachments.order(:filename)
    assert_equal ["first-#{@token}.txt", "second-#{@token}.pdf"], attachments.pluck(:filename)
    assert attachments.all?(&:unknown?)
    assert attachments.all? { |attachment| attachment.file.attached? }

    sign_in @current_user
    get report_sku_path(@sku.sku_code, tab: "basic"), headers: { "Accept" => "text/html" }
    assert_response :success
    assert_select "td", text: /first-#{@token}\.txt/
    assert_select "td", text: /second-#{@token}\.pdf/
    assert_select ".attachment-file-icon--pdf"
    assert_select "button[data-preview-kind='browser']"
    assert_select "button[data-preview-icon='bi-file-earmark-pdf']"
    assert_select "td", text: /未知/
  end

  test "updates attachment type inline and records the change" do
    attachment = create_attachment!("update body #{@token}")

    assert_difference -> { Ec::OperationLog.where(record_type: "Ec::Attachment", record_id: attachment.id, action: "update").count }, 1 do
      patch report_sku_attachment_path(@sku.sku_code, attachment),
            params: {
              inline_field: "attach_type",
              inline_context: { frame_id: "ignored", feedback_target: "ignored" },
              ec_attachment: { attach_type: "sales_contract" }
            },
            headers: { "Accept" => Mime[:turbo_stream].to_s }
    end

    assert_response :success
    assert_predicate attachment.reload, :sales_contract?
    log = Ec::OperationLog.where(record_type: "Ec::Attachment", record_id: attachment.id, action: "update").last
    assert_equal @current_user, log.user
    assert_equal [{ "field" => "attach_type", "from" => 2, "to" => 1 }], log.changeset
    assert_includes response.body, "销售合同"
  end

  test "previews browser supported attachments inline" do
    attachment = create_attachment!("preview body #{@token}")

    get preview_report_sku_attachment_path(@sku.sku_code, attachment)

    assert_response :success
    assert_match "inline", response.headers["Content-Disposition"]
    assert_equal "text/plain", response.media_type
    assert_equal "preview body #{@token}", response.body
  end

  test "rejects preview for unsupported archive attachments" do
    attachment = create_attachment!("archive body #{@token}", filename: "archive-#{@token}.zip", content_type: "application/zip")

    get preview_report_sku_attachment_path(@sku.sku_code, attachment)

    assert_response :unprocessable_entity
  end

  test "downloads a sku attachment" do
    attachment = create_attachment!("download body #{@token}")

    get report_sku_attachment_path(@sku.sku_code, attachment), headers: { "Accept" => "text/html" }

    assert_response :success
    assert_equal "download body #{@token}", response.body
    assert_match "attachment", response.headers["Content-Disposition"]
    assert_match "invoice-#{@token}.txt", response.headers["Content-Disposition"]
  end

  test "builds qiniu public attachment download url without service download" do
    attachment = fake_qiniu_attachment(bucket_private: false)
    url = ReportsController.new.send(:qiniu_attachment_download_url, attachment)

    assert_equal "https://assets.example.test/ec%2Fskus%2F2%2Fattachments%2Frobots.txt?attname=robots.txt", url
  end

  test "builds qiniu private attachment download url without service download" do
    attachment = fake_qiniu_attachment(bucket_private: true)
    captured_args = nil
    original_method = Qiniu::Auth.method(:authorize_download_url_2)
    Qiniu::Auth.define_singleton_method(:authorize_download_url_2) do |domain, key, args|
      captured_args = [domain, key, args]
      "signed-url"
    end

    begin
      assert_equal "signed-url", ReportsController.new.send(:qiniu_attachment_download_url, attachment)
    ensure
      Qiniu::Auth.define_singleton_method(:authorize_download_url_2, original_method)
    end

    domain, key, args = captured_args
    assert_equal "assets.example.test", domain
    assert_equal "ec/skus/2/attachments/robots.txt", key
    assert_equal :https, args.fetch(:schema)
    assert_equal ActiveStorage.service_urls_expire_in, args.fetch(:expires_in)
  end

  test "deletes a sku attachment and orphaned file" do
    attachment = create_attachment!("delete body #{@token}")
    blob_id = attachment.file.blob_id

    assert_difference -> { Ec::Attachment.count }, -1 do
      assert_difference -> { Ec::AttachmentLink.where(attachable: @sku).count }, -1 do
        delete report_sku_attachment_path(@sku.sku_code, attachment), headers: { "Accept" => "text/html" }
      end
    end

    assert_redirected_to report_sku_path(@sku.sku_code, tab: "basic")
    assert_not ActiveStorage::Blob.exists?(blob_id)
  end

  private

  def uploaded_file(body, filename: "invoice-#{@token}.txt", content_type: "text/plain")
    tempfile = Tempfile.new(["sku-attachment-#{@token}", ".txt"])
    tempfile.write(body)
    tempfile.rewind
    Rack::Test::UploadedFile.new(
      tempfile.path,
      content_type,
      false,
      original_filename: filename
    )
  end

  def create_attachment!(body, filename: "invoice-#{@token}.txt", content_type: "text/plain")
    attachment = Ec::Attachment.create!(
      attach_type: :invoice,
      oss_path: "ec/test/#{@token}/#{SecureRandom.uuid}/#{filename}",
      qiniu_hash: Digest::SHA256.hexdigest(body),
      filename: filename
    )
    attachment.attach_file!(io: StringIO.new(body), content_type: content_type)
    Ec::AttachmentLink.create!(attachable: @sku, ec_attachment: attachment)
    attachment
  end

  def fake_qiniu_attachment(bucket_private:)
    service = Struct.new(:bucket_private, :protocol, :domain).new(
      bucket_private,
      :https,
      "assets.example.test"
    )
    blob = Struct.new(:key).new("ec/skus/2/attachments/robots.txt")
    file = Struct.new(:service, :blob).new(service, blob)
    Struct.new(:file, :filename).new(file, "robots.txt")
  end

  def attachments_for_token
    Ec::Attachment.where("oss_path LIKE ? OR filename LIKE ?", "%#{@token}%", "%#{@token}%")
  end
end
