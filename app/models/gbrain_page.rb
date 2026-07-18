class GbrainPage < ApplicationRecord
  SYNC_STATUSES = %w[pending syncing synced pending_delete deleting failed].freeze
  PAGE_TYPES = {
    "platform-guide" => %w[platform-guides/],
    "region-profile" => %w[regions/],
    "category-strategy" => %w[category-strategies/],
    "operation-playbook" => %w[playbooks/],
    "policy" => %w[policies/],
    "case-study" => %w[cases/],
    "concept" => %w[concepts/],
    "source" => %w[sources/],
    "note" => %w[inbox/ notes/]
  }.freeze
  SOURCE_TIERS = %w[official internal-validated team-validated individual-experience third-party].freeze
  CONFIDENCE_LEVELS = %w[high medium low].freeze
  WIKI_CONTENT_ATTRIBUTES = %w[
    slug title page_type subtype aliases tags platform country region_scope category_scope
    effective_date reviewed_at review_after source_tier confidence summary content
  ].freeze

  before_validation :normalize_list_fields

  validates :slug, :content, :content_updated_at, presence: true
  validates :slug, uniqueness: true
  validates :sync_status, inclusion: { in: SYNC_STATUSES }
  with_options if: :wiki_fields_required? do
    validates :title, :page_type, :subtype, :aliases, :tags, :platform, :country,
      :reviewed_at, :review_after, :source_tier, :confidence, :summary, presence: true
    validates :slug, format: { with: /\A[a-z0-9][a-z0-9_\/-]*\z/ }
    validates :page_type, inclusion: { in: PAGE_TYPES.keys }
    validates :source_tier, inclusion: { in: SOURCE_TIERS }
    validates :confidence, inclusion: { in: CONFIDENCE_LEVELS }
  end
  validate :slug_cannot_change, on: :update
  validate :slug_matches_page_type, if: :wiki_fields_required?
  validate :required_type_scope, if: :wiki_fields_required?
  validate :review_after_reviewed_at, if: :wiki_fields_required?

  scope :recent_first, -> { order(content_updated_at: :desc, id: :desc) }

  def pending_deletion?
    delete_requested_at.present?
  end

  def aliases_text
    aliases.join("\n")
  end

  def aliases_text=(value)
    self.aliases = split_list(value)
  end

  def tags_text
    tags.join("\n")
  end

  def tags_text=(value)
    self.tags = split_list(value)
  end

  def region_scope_text
    region_scope.join("\n")
  end

  def region_scope_text=(value)
    self.region_scope = split_list(value)
  end

  def category_scope_text
    category_scope.join("\n")
  end

  def category_scope_text=(value)
    self.category_scope = split_list(value)
  end

  def compiled_content
    return content if page_type.blank?

    metadata = {
      "title" => title,
      "type" => page_type,
      "subtype" => subtype,
      "aliases" => aliases,
      "tags" => tags,
      "platform" => platform,
      "country" => country,
      "region_scope" => region_scope.presence,
      "category_scope" => category_scope.presence,
      "effective_date" => effective_date&.iso8601,
      "reviewed_at" => reviewed_at&.iso8601,
      "review_after" => review_after&.iso8601,
      "source_tier" => source_tier,
      "confidence" => confidence
    }.compact

    "#{YAML.dump(metadata)}---\n\n# #{title}\n\n> #{summary}\n\n#{content.strip}\n"
  end

  def preview_content
    return content if title.blank?

    "# #{title}\n\n> #{summary}\n\n#{content}"
  end

  def wiki_content_changed?
    WIKI_CONTENT_ATTRIBUTES.any? { |attribute| will_save_change_to_attribute?(attribute) }
  end

  private

  def wiki_fields_required?
    new_record? || page_type.present?
  end

  def normalize_list_fields
    self.aliases = normalize_list(aliases)
    self.tags = normalize_list(tags)
    self.region_scope = normalize_list(region_scope)
    self.category_scope = normalize_list(category_scope)
  end

  def normalize_list(values)
    Array(values).filter_map { |value| value.to_s.strip.presence }.uniq
  end

  def split_list(value)
    value.to_s.split(/[\n,，]+/).filter_map { |item| item.strip.presence }.uniq
  end

  def slug_cannot_change
    errors.add(:slug, I18n.t("admin.gbrain.errors.slug_readonly")) if will_save_change_to_slug?
  end

  def slug_matches_page_type
    prefixes = PAGE_TYPES[page_type]
    return if prefixes.blank? || prefixes.any? { |prefix| slug.to_s.start_with?(prefix) }

    errors.add(:slug, I18n.t("admin.gbrain.errors.slug_prefix", prefix: prefixes.join(" / ")))
  end

  def required_type_scope
    if page_type == "region-profile" && region_scope.blank?
      errors.add(:region_scope, :blank)
    end
    if page_type == "category-strategy" && category_scope.blank?
      errors.add(:category_scope, :blank)
    end
    if page_type == "policy" && effective_date.blank?
      errors.add(:effective_date, :blank)
    end
  end

  def review_after_reviewed_at
    return if reviewed_at.blank? || review_after.blank? || review_after >= reviewed_at

    errors.add(:review_after, I18n.t("admin.gbrain.errors.review_after"))
  end
end
