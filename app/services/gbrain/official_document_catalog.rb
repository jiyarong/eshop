require "digest"
require "uri"
require "yaml"

module Gbrain
  class OfficialDocumentCatalog
    ROOTS = { "ozon" => "ozon-docs-zh", "wb" => "wildberries_instructions_zh" }.freeze
    SOURCE_URLS = {
      "ozon" => "https://seller-edu.ozon.ru/libra",
      "wb" => "https://seller.wildberries.ru/instructions/ru/ru/categories"
    }.freeze
    VERSION = "official-seller-v1".freeze

    class InvalidSource < StandardError; end

    attr_reader :root, :entries, :manifests

    def initialize(directory:, platform: nil)
      @root = Pathname(directory).expand_path.realpath
      @entries = []
      @manifests = {}
      platforms = platform.present? ? [platform] : ROOTS.keys
      raise InvalidSource, "Unknown platform: #{platform}" unless (platforms - ROOTS.keys).empty?

      platforms.each { |key| scan_platform(key) }
      validate_identities!
      add_context
    end

    def self.parse(raw)
      match = raw.match(/\A---\s*\n(.*?)\n---\s*\n/m)
      metadata = match ? YAML.safe_load(match[1], permitted_classes: [Date, Time], aliases: false) : {}
      raise InvalidSource, "Front matter must be an object" unless metadata.nil? || metadata.is_a?(Hash)

      [JSON.parse((metadata || {}).to_json), match ? raw[match.end(0)..] : raw]
    rescue Psych::Exception => error
      raise InvalidSource, error.message
    end

    def self.without_title(body)
      body.sub(/^# [^\n]*\n?/, "").strip
    end

    def self.without_directory(body)
      body.gsub(/^## 本节目录\s*\n.*?(?=^## |\z)/m, "").strip
    end

    def read(entry)
      path = root.join(entry.fetch(:relative_path))
      raise InvalidSource, "Source escapes root: #{path}" unless path.realpath.to_s.start_with?("#{root}/")

      raw = File.binread(path).force_encoding(Encoding::UTF_8)
      unless raw.valid_encoding? && Digest::SHA256.hexdigest(raw) == entry.fetch(:raw_sha256)
        raise InvalidSource, "Source changed or is not UTF-8: #{path}"
      end
      raw
    end

    def report
      {
        documents: entries.size,
        platforms: entries.group_by { |entry| entry[:platform] }.transform_values(&:size),
        kinds: entries.group_by { |entry| entry[:document_kind] }.transform_values(&:size),
        bytes: entries.sum { |entry| entry[:bytes] },
        warnings: entries.flat_map { |entry| entry[:source_metadata]["warnings"] }.tally
      }
    end

    private

    def scan_platform(platform)
      base = root.join(ROOTS.fetch(platform))
      raise InvalidSource, "Missing source directory: #{base}" unless base.directory?

      manifest_path = base.join("manifest.json")
      manifests[platform] = manifest_path.file? ? File.binread(manifest_path).force_encoding("UTF-8") : nil
      manifest = manifests[platform] ? JSON.parse(manifests[platform]) : {}
      manifest_rows = Array(manifest["documents"]).index_by { |row| row.fetch("path") }
      files = base.glob("**/*.md").sort
      raise InvalidSource, "No Markdown files: #{base}" if files.empty?
      if platform == "wb"
        actual = files.reject { |path| path.basename.to_s == "README.md" }.map { |path| path.relative_path_from(base).to_s }
        unless actual.sort == manifest_rows.keys.sort && manifest_rows.values.all? { |row| row["status"] == "ok" }
          raise InvalidSource, "WB manifest and Markdown files do not match"
        end
      end

      files.each do |path|
        raise InvalidSource, "Source escapes root: #{path}" unless path.realpath.to_s.start_with?("#{root}/")

        raw = File.binread(path).force_encoding("UTF-8")
        raise InvalidSource, "Source is not UTF-8: #{path}" unless raw.valid_encoding?

        metadata, body = self.class.parse(raw)
        local_path = path.relative_path_from(base).to_s
        index = local_path == "README.md"
        title = metadata["title"].presence || body[/^# (.+)$/, 1]
        url = index ? SOURCE_URLS.fetch(platform) : metadata[platform == "ozon" ? "url" : "source_url"]
        raise InvalidSource, "Missing title or source URL: #{path}" if title.blank? || url.blank?
        uri = URI.parse(url)
        raise InvalidSource, "Invalid source URL: #{path}" unless uri.is_a?(URI::HTTPS) && uri.host.present?

        kind = if index
          "collection_index"
        elsif metadata["type"] == "section"
          self.class.without_directory(self.class.without_title(body)).empty? ? "directory" : "mixed"
        else
          "article"
        end
        suffix = index ? "index" : (platform == "ozon" ? local_path.delete_suffix(".md") : uri.path.split("/").last)
        warnings = []
        updated = metadata[platform == "ozon" ? "updated" : "updated_at"].to_s
        warnings << "unknown_official_updated_at" if !index && !updated.match?(/\A\d{4}-\d{2}-\d{2}/)
        warnings << "raw_markdown_over_100kb" if raw.bytesize >= 100.kilobytes
        warnings << "classification_context_sampled" if raw.bytesize > 40_000
        history = local_path.start_with?("digest/") || local_path.match?(/(?:archive|arhiv)/)
        entries << {
          platform: platform, relative_path: path.relative_path_from(root).to_s,
          source_key: url, source_url: url, target_slug: "sources/#{platform}/seller-guide/#{suffix}".downcase,
          title: title, document_kind: kind, raw_sha256: Digest::SHA256.hexdigest(raw), bytes: raw.bytesize,
          priority: { "collection_index" => 3, "directory" => 2 }.fetch(kind, history ? 1 : 0),
          source_metadata: {
            "front_matter" => metadata, "original_title" => manifest_rows.dig(local_path, "title"),
            "official_updated_raw" => updated.presence, "warnings" => warnings,
            "historical" => history, "local_path" => local_path,
            "source_retrieved_at" => manifest["retrieved_at"]
          }
        }
      end
    end

    def validate_identities!
      %i[target_slug source_key].each do |key|
        duplicates = entries.group_by { |entry| entry.fetch(key) }.select { |_, group| group.size > 1 }
        raise InvalidSource, "Duplicate #{key}: #{duplicates.keys.join(', ')}" if duplicates.any?
      end
      entries.each do |entry|
        slug = entry.fetch(:target_slug)
        raise InvalidSource, "Invalid slug: #{slug}" unless slug.length <= 200 && slug.match?(/\A[a-z0-9][a-z0-9_\/-]*\z/)
      end
    end

    def add_context
      by_path = entries.index_by { |entry| entry[:relative_path] }
      wb_readme = root.join(ROOTS.fetch("wb"), "README.md")
      wb_categories = wb_readme.file? ? wb_readme.read.scan(%r{\[([^\]]+)\]\(([^/]+)\/\)}).to_h.invert : {}
      entries.each do |entry|
        metadata = entry.fetch(:source_metadata)
        parts = metadata.fetch("local_path").delete_suffix(".md").split("/")
        ancestors = (1...parts.length).map { |length| "#{ROOTS.fetch(entry[:platform])}/#{parts.first(length).join('/')}.md" }
        metadata["ancestor_titles"] = ancestors.filter_map { |path| by_path.dig(path, :title) }
        metadata["ancestor_titles"] = [wb_categories[parts.first], *parts[0...-1]].compact if entry[:platform] == "wb"
        _, body = self.class.parse(read(entry))
        metadata["resolved_links"] = body.scan(/\]\(([^\s)]+)\)/).flatten.each_with_object({}) do |link, mapping|
          next if link.match?(/\A(?:[a-z]+:|\/|#)/i)

          target, anchor = link.split("#", 2)
          target, query = target.split("?", 2)
          destination = Pathname(entry[:relative_path]).dirname.join(URI::DEFAULT_PARSER.unescape(target)).cleanpath.to_s
          next unless (found = by_path[destination])

          mapping[link] = "#{found[:source_url]}#{query ? "?#{query}" : ''}#{anchor ? "##{anchor}" : ''}"
        end
        if entry[:document_kind] == "collection_index"
          metadata["index_links"] = body.lines.filter_map do |line|
            next unless line.match?(/\A(?:## |\d+\. )\[/)
            label, link = line.scan(/\[([^\]]+)\]\(([^)]+)\)/).first
            next unless label && link

            target = metadata["resolved_links"][link]
            target ? "- [#{label}](#{target})" : "- #{label}"
          end
        end
        entry[:classification_input_sha256] = Digest::SHA256.hexdigest(
          [VERSION, entry[:raw_sha256], entry[:target_slug], metadata.except("source_retrieved_at").to_json].join("\n")
        )
      end
    end
  end
end
