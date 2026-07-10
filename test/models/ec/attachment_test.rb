require "test_helper"

class Ec::AttachmentTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(4).upcase
  end

  teardown do
    if defined?(Ec::Attachment)
      Ec::Attachment.where("oss_path LIKE ?", "%#{@token}%").find_each do |attachment|
        attachment.file.purge if attachment.respond_to?(:file)
      end
    end
    Ec::AttachmentLink.where(attachable_type: "Ec::Sku", attachable_id: skus_for_token.select(:id)).delete_all if defined?(Ec::AttachmentLink)
    Ec::Attachment.where("oss_path LIKE ?", "%#{@token}%").delete_all if defined?(Ec::Attachment)
    skus_for_token.delete_all if defined?(Ec::Sku)
  end

  test "stores oss metadata with an attachment type enum" do
    attachment = Ec::Attachment.create!(
      attach_type: :sales_contract,
      oss_path: "ec/test/#{@token}/contract.pdf",
      qiniu_hash: "hash-#{@token}",
      filename: "contract-#{@token}.pdf"
    )

    assert attachment.sales_contract?
    assert_equal 1, Ec::Attachment.attach_types.fetch("sales_contract")
    assert_equal "ec/test/#{@token}/contract.pdf", attachment.oss_path
    assert_equal "hash-#{@token}", attachment.qiniu_hash
    assert_equal "contract-#{@token}.pdf", attachment.filename
  end

  test "stores uploaded file through active storage" do
    attachment = Ec::Attachment.create!(
      attach_type: :invoice,
      oss_path: "ec/test/#{@token}/active-storage.txt",
      qiniu_hash: "hash-active-storage-#{@token}",
      filename: "active-storage-#{@token}.txt"
    )

    attachment.attach_file!(
      io: StringIO.new("attachment body #{@token}"),
      content_type: "text/plain"
    )

    assert attachment.file.attached?
    assert_equal "active-storage-#{@token}.txt", attachment.file.filename.to_s
    assert_equal "text/plain", attachment.file.content_type
    assert_equal attachment.oss_path, attachment.file.blob.key
  end

  test "links attachments to polymorphic business objects" do
    sku = Ec::Sku.create!(
      sku_code: "ATTACH-#{@token}",
      product_name: "Attachment test SKU"
    )
    attachment = Ec::Attachment.create!(
      attach_type: :invoice,
      oss_path: "ec/test/#{@token}/invoice.pdf",
      qiniu_hash: "hash-invoice-#{@token}",
      filename: "invoice-#{@token}.pdf"
    )

    link = Ec::AttachmentLink.create!(
      attachable: sku,
      ec_attachment: attachment
    )

    assert_equal sku, link.attachable
    assert_equal attachment, link.ec_attachment
    assert_includes attachment.attachment_links, link
    assert_includes sku.attachments, attachment
  end

  private

  def skus_for_token
    Ec::Sku.with_deleted.where("sku_code LIKE ?", "%#{@token}%")
  end
end
