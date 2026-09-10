require "mini_magick"
require "tmpdir"

module ErpAI
  class CompetitorImageCombiner
    CELL_SIZE = 1_200
    IMAGE_COUNT = 4

    def self.call(uploaded_files)
      new(uploaded_files).call
    end

    def initialize(uploaded_files)
      @uploaded_files = Array(uploaded_files)
    end

    def call
      raise ArgumentError, "images_count_must_be_4" unless uploaded_files.size == IMAGE_COUNT

      Dir.mktmpdir("competitor-images") do |directory|
        image_paths = uploaded_files.each_with_index.map do |uploaded_file, index|
          normalized_image_path(uploaded_file, directory, index)
        end
        row_paths = image_paths.each_slice(2).with_index.map do |paths, index|
          joined_image_path(paths, directory, "row-#{index}.png", "+append")
        end
        output_path = joined_image_path(row_paths, directory, "combined.jpg", "-append")
        output = MiniMagick::Image.open(output_path)
        output.strip
        output.quality 88
        output.to_blob
      end
    end

    private

    attr_reader :uploaded_files

    def normalized_image_path(uploaded_file, directory, index)
      image = MiniMagick::Image.open(uploaded_file.tempfile.path)
      image.auto_orient
      image.resize "#{CELL_SIZE}x#{CELL_SIZE}>"
      image.background "white"
      image.gravity "center"
      image.extent "#{CELL_SIZE}x#{CELL_SIZE}"
      path = File.join(directory, "#{index}.png")
      image.format "png"
      image.write(path)
      path
    end

    def joined_image_path(image_paths, directory, filename, append_operator)
      path = File.join(directory, filename)
      MiniMagick.convert do |convert|
        image_paths.each { |image_path| convert << image_path }
        convert.background "white"
        convert << append_operator
        convert << path
      end
      path
    end
  end
end
