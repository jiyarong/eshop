require "yaml"

class SkillManifest
  Error = Class.new(StandardError)
  NAME_PATTERN = /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/

  attr_reader :name, :description, :body

  def self.parse(content)
    new(content).tap(&:validate!)
  end

  def initialize(content)
    @content = content.to_s.dup.force_encoding(Encoding::UTF_8)
  end

  def validate!
    raise Error, message(:invalid_encoding) unless @content.valid_encoding?

    match = @content.match(/\A---[ \t]*\r?\n(.*?)\r?\n---[ \t]*\r?\n(.*)\z/m)
    raise Error, message(:frontmatter_required) unless match

    metadata = YAML.safe_load(match[1], permitted_classes: [], permitted_symbols: [], aliases: false)
    raise Error, message(:frontmatter_mapping) unless metadata.is_a?(Hash)
    raise Error, message(:frontmatter_fields) unless metadata.keys.sort == %w[description name]

    @name = metadata["name"]
    @description = metadata["description"]
    @body = match[2]

    raise Error, message(:invalid_name) unless @name.is_a?(String) && @name.length <= 64 && @name.match?(NAME_PATTERN)
    raise Error, message(:description_required) unless @description.is_a?(String) && @description.strip.present?
    raise Error, message(:body_required) if @body.strip.blank?

    self
  rescue Psych::Exception => error
    raise Error, message(:invalid_yaml, message: error.message)
  end

  private

  def message(key, **options)
    I18n.t("admin.skills.errors.#{key}", **options)
  end
end
