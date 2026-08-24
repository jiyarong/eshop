require "test_helper"

class Erp::SuppliersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(4).upcase
    @current_user = create_user_with_roles("erp-suppliers-#{@token.downcase}@example.com", "manager")
    sign_in @current_user
    @supplier = Ec::Company.create!(
      name: "供应商 #{@token}", tags: [ "supplier" ], origin: "浙江",
      invoice_type: "special", channel: "online", online_url: "https://example.com/#{@token}",
      developer: @current_user, purchaser: @current_user, factory_audited: true,
      credit_terms: true, supplier_grade: "A", supplier_evaluation: "配合度高"
    )
    @broker = Ec::Company.create!(name: "报关行 #{@token}", tags: [ "customs_broker" ])
  end

  teardown do
    company_ids = Ec::Company.where("name LIKE ?", "%#{@token}%").pluck(:id)
    attachment_ids = attachments_for_token.pluck(:id)
    Ec::SkuBatch.where(supplier_id: company_ids).update_all(supplier_id: nil)
    attachments_for_token.find_each do |attachment|
      attachment.file.purge if attachment.file.attached?
      attachment.destroy!
    end
    Ec::OperationLog.where(record_type: "Ec::Attachment", record_id: attachment_ids).delete_all
    Ec::AttachmentLink.where(attachable_type: "Ec::Company", attachable_id: company_ids).delete_all
    Ec::Company.where(id: company_ids).delete_all
    UserRole.joins(:user).where("users.email LIKE ?", "erp-suppliers-#{@token.downcase}%").delete_all
    User.where("email LIKE ?", "erp-suppliers-#{@token.downcase}%").delete_all
  end

  test "index renders supplier companies but excludes other company tags" do
    get erp_suppliers_path, headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", "供应商维护"
    assert_select "td", text: @supplier.name
    assert_select "td", text: @broker.name, count: 0
    assert_select "th", text: "供应商等级"
  end

  test "index paginates suppliers and preserves filters" do
    22.times do |index|
      Ec::Company.create!(
        name: format("分页供应商 %02d %s", index, @token),
        tags: [ "supplier" ],
        origin: "分页产地 #{@token}",
        is_active: true
      )
    end

    get erp_suppliers_path,
        params: { q: "分页供应商", status: "active", page: 2 },
        headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select ".prod-tbl tbody tr", count: 10
    assert_select ".inventory-pagination-bar .pagination-chip", "第 2/3 页"
    assert_select ".inventory-pagination-bar", /显示第 11-20 条，共 22 条/
    assert_select ".inventory-pagination-bar .pg-btn.on", "2"
    assert_select ".inventory-pagination-bar a[href*='page=1'][href*='q=%E5%88%86%E9%A1%B5%E4%BE%9B%E5%BA%94%E5%95%86'][href*='status=active']"
    assert_select ".inventory-pagination-bar form[action='#{erp_suppliers_path}'] input[name='q'][value='分页供应商']"
    assert_select ".inventory-pagination-bar form input[name='status'][value='active']"
  end

  test "show renders supplier fields and attachment controls" do
    get erp_supplier_path(@supplier), headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", @supplier.name
    assert_select "dt", text: "是否验厂"
    assert_select "dd", text: "是"
    assert_select "form[action='#{attachments_erp_supplier_path(@supplier)}']"
    assert_select "select[name='ec_attachment[attach_type]'] option[value='business_license']", "营业执照"
    assert_select "input[type='file'][name='ec_attachment[files][]'][multiple]"
    assert_select "#supplier-#{@supplier.id}-attachments-upload-dialog"
    assert_select "dialog.attachment-preview-dialog"
    assert_select "td.empty-state", text: "暂无附件"
  end

  test "new modal renders full supplier form" do
    get erp_new_supplier_path, headers: { "Accept" => "text/html", "Turbo-Frame" => "erp_modal" }

    assert_response :success
    assert_select "turbo-frame#erp_modal"
    assert_select "input[name='ec_company[name]']"
    assert_select "select[name='ec_company[supplier_grade]'] option[value='S']"
  end

  test "create persists supplier company fields" do
    assert_difference "Ec::Company.count", 1 do
      post erp_suppliers_path, params: {
        ec_company: {
          name: "新供应商 #{@token}", tags: [ "supplier" ], origin: "广东",
          invoice_type: "general", channel: "offline", developer_id: @current_user.id,
          purchaser_id: @current_user.id, factory_audited: "1", credit_terms: "0",
          supplier_grade: "s", supplier_evaluation: "交货稳定", is_active: "1"
        }
      }
    end

    created = Ec::Company.find_by!(name: "新供应商 #{@token}")
    assert_redirected_to erp_supplier_path(created)
    assert_equal [ "supplier" ], created.tags
    assert_equal "S", created.supplier_grade
    assert_predicate created, :factory_audited?
  end

  test "association create responds with the reusable picker event payload" do
    post erp_suppliers_path, params: {
      association_dom_id: "batch-company-picker",
      ec_company: { name: "弹窗供应商 #{@token}", tags: [ "supplier" ], is_active: "1" }
    }, headers: { "Accept" => "text/html", "Turbo-Frame" => "association_create_modal" }

    assert_response :success
    created = Ec::Company.find_by!(name: "弹窗供应商 #{@token}")
    assert_select "turbo-frame#association_create_modal"
    assert_select "[data-controller='association-created'][data-association-created-picker-id-value='batch-company-picker'][data-association-created-record-id-value='#{created.id}']"
  end

  test "company search is fuzzy and can be limited by tag" do
    get search_erp_companies_path, params: { q: @token.downcase, tag: "supplier" }, as: :json

    assert_response :success
    body = response.parsed_body
    assert_equal [ @supplier.id ], body.map { |item| item.fetch("id") }
    assert_equal @supplier.name, body.first.fetch("label")
  end

  test "index and show retain JSON responses" do
    get erp_suppliers_path(format: :json)
    assert_response :success
    assert_includes response.parsed_body.map { |item| item.fetch("id") }, @supplier.id

    sign_in @current_user
    get erp_supplier_path(@supplier, format: :json)
    assert_response :success
    assert_equal @supplier.name, response.parsed_body.fetch("name")
  end

  test "uploads and lists multiple supplier attachments" do
    assert_difference -> { Ec::Attachment.count }, 2 do
      assert_difference -> { Ec::AttachmentLink.where(attachable: @supplier).count }, 2 do
        post attachments_erp_supplier_path(@supplier), params: {
          ec_attachment: {
            attach_type: "business_license",
            files: [
              uploaded_file("first #{@token}", filename: "license-#{@token}.txt"),
              uploaded_file("second #{@token}", filename: "certificate-#{@token}.pdf", content_type: "application/pdf")
            ]
          }
        }
      end
    end

    assert_redirected_to erp_supplier_path(@supplier)
    attachments = @supplier.attachments.order(:filename)
    assert_equal ["certificate-#{@token}.pdf", "license-#{@token}.txt"], attachments.pluck(:filename)
    assert attachments.all?(&:business_license?)
    assert attachments.all? { |attachment| attachment.file.attached? }

    get erp_supplier_path(@supplier), headers: { "Accept" => "text/html" }
    assert_response :success
    assert_select "td", text: /license-#{@token}\.txt/
    assert_select "td", text: /certificate-#{@token}\.pdf/
    assert_select ".attachment-file-icon--pdf"
    assert_select "button[data-preview-kind='browser']"
  end

  test "updates supplier attachment type inline and records the change" do
    attachment = create_attachment!("update #{@token}", attachable: @supplier, attach_type: :unknown)

    assert_difference -> { Ec::OperationLog.where(record_type: "Ec::Attachment", record_id: attachment.id, action: "update").count }, 1 do
      patch attachment_erp_supplier_path(@supplier, attachment),
            params: {
              inline_field: "attach_type",
              ec_attachment: { attach_type: "framework_agreement" }
            },
            headers: { "Accept" => Mime[:turbo_stream].to_s }
    end

    assert_response :success
    assert_predicate attachment.reload, :framework_agreement?
    assert_includes response.body, "框架协议"
  end

  test "previews and downloads supplier attachment" do
    attachment = create_attachment!("attachment body #{@token}", attachable: @supplier)

    get preview_attachment_erp_supplier_path(@supplier, attachment)
    assert_response :success
    assert_equal "inline", response.headers["Content-Disposition"].split(";").first
    assert_equal "text/plain", response.media_type
    assert_equal "attachment body #{@token}", response.body

    get attachment_erp_supplier_path(@supplier, attachment)
    assert_response :success
    assert_match "attachment", response.headers["Content-Disposition"]
    assert_match attachment.filename, response.headers["Content-Disposition"]
  end

  test "attachment actions cannot access another supplier attachment" do
    other_supplier = Ec::Company.create!(name: "其他供应商 #{@token}", tags: [ "supplier" ])
    attachment = create_attachment!("private #{@token}", attachable: other_supplier)

    get attachment_erp_supplier_path(@supplier, attachment)
    assert_response :not_found

    get preview_attachment_erp_supplier_path(@supplier, attachment)
    assert_response :not_found

    delete attachment_erp_supplier_path(@supplier, attachment)
    assert_response :not_found
    assert Ec::Attachment.exists?(attachment.id)
  end

  test "deletes a supplier attachment and orphaned file" do
    attachment = create_attachment!("delete #{@token}", attachable: @supplier)

    blob_id = attachment.file.blob_id
    assert_difference -> { Ec::Attachment.count }, -1 do
      assert_difference -> { Ec::AttachmentLink.where(attachable: @supplier).count }, -1 do
        delete attachment_erp_supplier_path(@supplier, attachment)
      end
    end
    assert_redirected_to erp_supplier_path(@supplier)
    assert_not ActiveStorage::Blob.exists?(blob_id)
  end

  private

  def uploaded_file(body, filename: "license-#{@token}.txt", content_type: "text/plain")
    tempfile = Tempfile.new([ "supplier-attachment-#{@token}", ".txt" ])
    tempfile.write(body)
    tempfile.rewind
    Rack::Test::UploadedFile.new(
      tempfile.path,
      content_type,
      false,
      original_filename: filename
    )
  end

  def create_attachment!(body, attachable:, attach_type: :business_license, filename: "license-#{@token}.txt")
    attachment = Ec::Attachment.create!(
      attach_type: attach_type,
      oss_path: "ec/test/#{@token}/#{SecureRandom.uuid}/#{filename}",
      qiniu_hash: Digest::SHA256.hexdigest(body),
      filename: filename
    )
    attachment.attach_file!(io: StringIO.new(body), content_type: "text/plain")
    Ec::AttachmentLink.create!(attachable: attachable, ec_attachment: attachment)
    attachment
  end

  def attachments_for_token
    Ec::Attachment.where("oss_path LIKE ? OR filename LIKE ?", "%#{@token}%", "%#{@token}%")
  end
end
