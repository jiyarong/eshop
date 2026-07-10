require "zip"

class SkillPackage
  Error = Class.new(StandardError)
  Package = Struct.new(:name, :description, :skill_md, :archive_data, keyword_init: true)

  MAX_ARCHIVE_BYTES = 20.megabytes
  MAX_UNCOMPRESSED_BYTES = 50.megabytes
  MAX_ENTRIES = 500

  class << self
    def from_markdown(skill_md)
      manifest = SkillManifest.parse(skill_md)
      files = { "SKILL.md" => skill_md.to_s }
      package(manifest, files)
    end

    def from_upload(upload)
      raise Error, message(:zip_required) unless upload

      data = upload.read
      upload.rewind if upload.respond_to?(:rewind)
      raise Error, message(:zip_too_large) if data.bytesize > MAX_ARCHIVE_BYTES

      from_zip_data(data)
    rescue Zip::Error, Errno::ENOENT => error
      raise Error, message(:invalid_zip, message: error.message)
    end

    def replace_skill_md(archive_data, skill_md)
      manifest = SkillManifest.parse(skill_md)
      current = read_zip(archive_data)
      current[:files]["SKILL.md"] = skill_md.to_s
      package(manifest, current[:files])
    rescue Zip::Error => error
      raise Error, message(:invalid_stored_zip, message: error.message)
    end

    private

    def from_zip_data(data)
      archive = read_zip(data)
      skill_md = archive[:files].fetch("SKILL.md")
      manifest = SkillManifest.parse(skill_md)

      if archive[:root].present? && archive[:root] != manifest.name
        raise Error, message(:folder_mismatch)
      end

      package(manifest, archive[:files])
    rescue KeyError
      raise Error, message(:single_manifest)
    rescue SkillManifest::Error => error
      raise Error, error.message
    end

    def read_zip(data)
      files = {}
      root = nil
      declared_size = 0
      actual_size = 0
      manifest_paths = []

      Zip::File.open_buffer(StringIO.new(data)) do |zip|
        entries = zip.entries.reject { |entry| entry.directory? || ignored_entry?(entry.name) }
        raise Error, message(:too_many_files) if entries.length > MAX_ENTRIES

        entries.each do |entry|
          validate_path!(entry.name)
          declared_size += entry.size
          raise Error, message(:expanded_too_large) if declared_size > MAX_UNCOMPRESSED_BYTES
          manifest_paths << entry.name if File.basename(entry.name) == "SKILL.md"
        end

        raise Error, message(:single_manifest) unless manifest_paths.one?

        manifest_path = manifest_paths.first
        parts = manifest_path.split("/")
        raise Error, message(:manifest_depth) unless [ 1, 2 ].include?(parts.length)
        root = parts.length == 2 ? parts.first : nil

        entries.each do |entry|
          if root.present?
            raise Error, message(:single_folder) unless entry.name.start_with?("#{root}/")
            relative_path = entry.name.delete_prefix("#{root}/")
          else
            relative_path = entry.name
          end
          raise Error, message(:duplicate_paths) if files.key?(relative_path)

          remaining_bytes = MAX_UNCOMPRESSED_BYTES - actual_size
          content = entry.get_input_stream.read(remaining_bytes + 1) || "".b
          raise Error, message(:expanded_too_large) if content.bytesize > remaining_bytes

          actual_size += content.bytesize
          files[relative_path] = content
        end
      end

      { root: root, files: files }
    end

    def package(manifest, files)
      Package.new(
        name: manifest.name,
        description: manifest.description,
        skill_md: files.fetch("SKILL.md"),
        archive_data: build_zip(manifest.name, files)
      )
    end

    def build_zip(name, files)
      Zip::OutputStream.write_buffer do |zip|
        files.sort.each do |relative_path, content|
          zip.put_next_entry("#{name}/#{relative_path}")
          zip.write(content)
        end
      end.string
    end

    def ignored_entry?(name)
      name.start_with?("__MACOSX/") || File.basename(name) == ".DS_Store"
    end

    def validate_path!(path)
      clean = path.tr("\\", "/")
      segments = clean.split("/")
      if clean.start_with?("/") || clean.match?(/\A[A-Za-z]:\//) || segments.include?("..") || segments.include?(".")
        raise Error, message(:unsafe_path)
      end
    end

    def message(key, **options)
      I18n.t("admin.skills.errors.#{key}", **options)
    end
  end
end
