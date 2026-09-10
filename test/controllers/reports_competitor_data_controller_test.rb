require "test_helper"

class ReportsCompetitorDataControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(4).upcase
    @user = create_user_with_roles("competitor-report-#{@token.downcase}@example.com", "manager")
    sign_in @user
    @sku = Ec::Sku.create!(sku_code: "COMP-REPORT-#{@token}", product_name: "Competitor Report SKU")
    @batch = @sku.competitor_data_batches.create!
    @datum = @batch.competitor_data.build(markdown: "# Visible competitor\n\nUnique #{@token}")
    @datum.combined_image.attach(
      io: StringIO.new("image #{@token}"),
      filename: "competitor-#{@token}.jpg",
      content_type: "image/jpeg"
    )
    @datum.save!
  end

  teardown do
    @sku&.competitor_data_batches&.find_each do |batch|
      batch.competitor_data.each do |datum|
        datum.combined_image.purge if datum.combined_image.attached?
      end
      batch.destroy!
    end
    Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
    UserRole.where(user_id: [ @user&.id, @viewer&.id ]).delete_all
    User.where(id: [ @user&.id, @viewer&.id ]).delete_all
  end

  test "renders competitor batches and markdown in the sku detail tab" do
    get report_sku_path(@sku.sku_code, tab: "competitor_data"), headers: { "Accept" => "text/html" }

    assert_response :success
    assert_select ".sku-detail-tabs__link[aria-current='page']", text: "竞品数据"
    assert_select ".competitor-data-batch", count: 1
    assert_select ".competitor-data-card", count: 1
    assert_select "[data-controller='markdown'] [data-markdown-target='source']", text: /Unique #{@token}/
    assert_select ".competitor-data-card__image[loading='lazy']", count: 1
    assert_select "a[data-turbo-method='delete']", count: 2
  end

  test "deletes one competitor without deleting its batch" do
    blob_id = @datum.combined_image.blob_id

    assert_difference -> { Ec::CompetitorDatum.count }, -1 do
      assert_no_difference -> { Ec::CompetitorDataBatch.count } do
        delete report_sku_competitor_datum_path(@sku.sku_code, @batch, @datum),
          headers: { "Accept" => "text/html" }
      end
    end

    assert_redirected_to report_sku_path(@sku.sku_code, tab: "competitor_data")
    assert_not ActiveStorage::Blob.exists?(blob_id)
  end

  test "deletes a complete competitor batch" do
    blob_id = @datum.combined_image.blob_id

    assert_difference -> { Ec::CompetitorDataBatch.count }, -1 do
      assert_difference -> { Ec::CompetitorDatum.count }, -1 do
        delete report_sku_competitor_data_batch_path(@sku.sku_code, @batch),
          headers: { "Accept" => "text/html" }
      end
    end

    assert_redirected_to report_sku_path(@sku.sku_code, tab: "competitor_data")
    assert_not ActiveStorage::Blob.exists?(blob_id)
  end

  test "read only users can view but cannot delete competitor data" do
    @viewer = create_user_with_roles("competitor-report-viewer-#{@token.downcase}@example.com", "auditor")
    sign_out @user
    sign_in @viewer

    get report_sku_path(@sku.sku_code, tab: "competitor_data"), headers: { "Accept" => "text/html" }
    assert_response :success
    assert_select "a[data-turbo-method='delete']", count: 0

    sign_in @viewer
    delete report_sku_competitor_data_batch_path(@sku.sku_code, @batch),
      headers: { "Accept" => "text/html" }
    assert_response :forbidden
    assert Ec::CompetitorDataBatch.exists?(@batch.id)
  end
end
