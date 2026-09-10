require "test_helper"
require "mini_magick"

class ErpAI::V2::CompetitorDataBatchesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = SecureRandom.hex(4).upcase
    @user = create_user_with_roles("competitor-api-#{@token.downcase}@example.com", "manager")
    @raw_api_token, = UserApiKey.generate_for!(@user, name: "Competitor API")
    @sku = Ec::Sku.create!(sku_code: "COMP-#{@token}", product_name: "Competitor API SKU")
    @image_files = create_image_files
    @invalid_image = Tempfile.new([ "competitor-invalid-#{@token}", ".png" ])
    @invalid_image.write("not an image")
    @invalid_image.close
  end

  teardown do
    @sku&.competitor_data_batches&.find_each do |batch|
      batch.competitor_data.each do |datum|
        datum.combined_image.purge if datum.combined_image.attached?
      end
      batch.destroy!
    end
    @image_files.to_a.each(&:unlink)
    @invalid_image&.unlink
    UserApiKey.where(user_id: [ @user&.id, @viewer&.id ]).delete_all
    UserRole.where(user_id: [ @user&.id, @viewer&.id ]).delete_all
    User.where(id: [ @user&.id, @viewer&.id ]).delete_all
    Ec::Sku.with_deleted.where(id: @sku&.id).delete_all
  end

  test "uploads one batch with five competitor records and combined images" do
    assert_difference -> { Ec::CompetitorDataBatch.count }, 1 do
      assert_difference -> { Ec::CompetitorDatum.count }, 5 do
        assert_difference -> { ActiveStorage::Attachment.where(name: "combined_image").count }, 5 do
          post "/ai/v2/skus/competitor_data_batches",
            params: { sku_code: @sku.sku_code.downcase, competitors: indexed_competitor_params(5) },
            headers: bearer_headers
        end
      end
    end

    assert_response :created
    assert_equal @sku.sku_code, response.parsed_body.dig("data", "sku_code")
    assert_equal 5, response.parsed_body.dig("data", "competitor_count")

    batch = @sku.competitor_data_batches.includes(competitor_data: { combined_image_attachment: :blob }).last
    assert_equal 5, batch.competitor_data.size
    assert_equal "# Competitor 1\n\nDetails 1", batch.competitor_data.first.markdown
    assert batch.competitor_data.all? { |datum| datum.combined_image.attached? }
    assert batch.competitor_data.all? { |datum| datum.combined_image.blob.content_type == "image/jpeg" }
  end

  test "rejects batches outside the five to eight competitor range" do
    assert_no_difference -> { Ec::CompetitorDataBatch.count } do
      post "/ai/v2/skus/competitor_data_batches",
        params: { sku_code: @sku.sku_code, competitors: competitor_params(4) },
        headers: bearer_headers
    end

    assert_response :unprocessable_entity
    assert_equal "competitors_count_must_be_between_5_and_8", response.parsed_body.fetch("error")
  end

  test "requires four images for every competitor" do
    competitors = competitor_params(5)
    competitors.last[:images] = competitors.last[:images].first(3)

    assert_no_difference -> { Ec::CompetitorDataBatch.count } do
      post "/ai/v2/skus/competitor_data_batches",
        params: { sku_code: @sku.sku_code, competitors: competitors },
        headers: bearer_headers
    end

    assert_response :unprocessable_entity
    assert_equal "images_count_must_be_4", response.parsed_body.fetch("error")
  end

  test "requires competitors and nonblank markdown" do
    post "/ai/v2/skus/competitor_data_batches",
      params: { sku_code: @sku.sku_code },
      headers: bearer_headers
    assert_response :bad_request
    assert_equal "competitors is required", response.parsed_body.fetch("error")

    competitors = competitor_params(5)
    competitors.first[:markdown] = " "
    post "/ai/v2/skus/competitor_data_batches",
      params: { sku_code: @sku.sku_code, competitors: competitors },
      headers: bearer_headers

    assert_response :unprocessable_entity
    assert_equal "markdown_is_required", response.parsed_body.fetch("error")
  end

  test "rejects invalid images and cleans images already uploaded for the batch" do
    competitors = competitor_params(5)
    competitors.last[:images][-1] = Rack::Test::UploadedFile.new(@invalid_image.path, "image/png")

    assert_no_difference -> { Ec::CompetitorDataBatch.count } do
      assert_no_difference -> { ActiveStorage::Blob.count } do
        post "/ai/v2/skus/competitor_data_batches",
          params: { sku_code: @sku.sku_code, competitors: competitors },
          headers: bearer_headers
      end
    end

    assert_response :unprocessable_entity
    assert_equal "invalid_image", response.parsed_body.fetch("error")
  end

  test "requires authentication and sku management permission" do
    post "/ai/v2/skus/competitor_data_batches",
      params: { sku_code: @sku.sku_code, competitors: competitor_params(5) }
    assert_response :unauthorized

    @viewer = create_user_with_roles("competitor-viewer-#{@token.downcase}@example.com", "auditor")
    viewer_token, = UserApiKey.generate_for!(@viewer, name: "Competitor API Viewer")
    post "/ai/v2/skus/competitor_data_batches",
      params: { sku_code: @sku.sku_code, competitors: competitor_params(5) },
      headers: { "Authorization" => "Bearer #{viewer_token}" }

    assert_response :forbidden
    assert_equal "Forbidden", response.parsed_body.fetch("error")
  end

  private

  def bearer_headers
    { "Authorization" => "Bearer #{@raw_api_token}" }
  end

  def competitor_params(count)
    Array.new(count) do |index|
      {
        markdown: "# Competitor #{index + 1}\n\nDetails #{index + 1}",
        images: @image_files.map { |file| Rack::Test::UploadedFile.new(file.path, "image/png") }
      }
    end
  end

  def indexed_competitor_params(count)
    competitor_params(count).each_with_index.to_h { |competitor, index| [ index.to_s, competitor ] }
  end

  def create_image_files
    %w[red green blue yellow].map.with_index do |color, index|
      tempfile = Tempfile.new([ "competitor-api-#{@token}-#{index}", ".png" ])
      tempfile.close
      MiniMagick.convert do |convert|
        convert.size "20x20"
        convert << "xc:#{color}"
        convert << tempfile.path
      end
      tempfile
    end
  end
end
