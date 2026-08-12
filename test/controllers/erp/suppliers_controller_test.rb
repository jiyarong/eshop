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
    Ec::SkuBatch.where(supplier_id: company_ids).update_all(supplier_id: nil)
    attachments_for_token.find_each do |attachment|
      attachment.file.purge if attachment.file.attached?
      attachment.destroy!
    end
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

  test "show renders supplier fields and attachment controls" do
    get erp_supplier_path(@supplier), headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select "h1", @supplier.name
    assert_select "dt", text: "是否验厂"
    assert_select "dd", text: "是"
    assert_select "form[action='#{attachments_erp_supplier_path(@supplier)}']"
    assert_select "select[name='ec_attachment[attach_type]'] option[value='business_license']", "营业执照"
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

  test "uploads and deletes a business license" do
    assert_difference -> { Ec::Attachment.count }, 1 do
      assert_difference -> { Ec::AttachmentLink.where(attachable: @supplier).count }, 1 do
        post attachments_erp_supplier_path(@supplier), params: {
          ec_attachment: { attach_type: "business_license", file: uploaded_file("license #{@token}") }
        }
      end
    end

    attachment = @supplier.attachments.first
    assert_redirected_to erp_supplier_path(@supplier)
    assert_predicate attachment, :business_license?
    assert_predicate attachment.file, :attached?

    blob_id = attachment.file.blob_id
    sign_in @current_user
    assert_difference -> { Ec::Attachment.count }, -1 do
      delete attachment_erp_supplier_path(@supplier, attachment)
    end
    assert_not ActiveStorage::Blob.exists?(blob_id)
  end

  private

  def uploaded_file(body)
    tempfile = Tempfile.new([ "supplier-attachment-#{@token}", ".txt" ])
    tempfile.write(body)
    tempfile.rewind
    Rack::Test::UploadedFile.new(
      tempfile.path,
      "text/plain",
      false,
      original_filename: "license-#{@token}.txt"
    )
  end

  def attachments_for_token
    Ec::Attachment.where("oss_path LIKE ? OR filename LIKE ?", "%#{@token}%", "%#{@token}%")
  end
end
