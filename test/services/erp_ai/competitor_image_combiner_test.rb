require "test_helper"
require "mini_magick"

class ErpAI::CompetitorImageCombinerTest < ActiveSupport::TestCase
  setup do
    @tempfiles = %w[red green blue yellow].map.with_index do |color, index|
      tempfile = Tempfile.new([ "competitor-source-#{index}", ".png" ])
      tempfile.close
      MiniMagick.convert do |convert|
        convert.size "40x20"
        convert << "xc:#{color}"
        convert << tempfile.path
      end
      tempfile
    end
  end

  teardown do
    @tempfiles.each(&:unlink)
  end

  test "combines four uploaded images into a fixed two by two jpeg" do
    uploads = @tempfiles.map do |tempfile|
      Rack::Test::UploadedFile.new(tempfile.path, "image/png")
    end

    combined = ErpAI::CompetitorImageCombiner.call(uploads)
    image = MiniMagick::Image.read(combined)

    assert_equal [ 2_400, 2_400 ], image.dimensions
    assert_equal "JPEG", image.type
  end

  test "requires exactly four images" do
    error = assert_raises(ArgumentError) do
      ErpAI::CompetitorImageCombiner.call([])
    end

    assert_equal "images_count_must_be_4", error.message
  end
end
