module Ec
  class SkuProfitVersion < ApplicationRecord
    include Ec::Auditable

    self.table_name = "ec_sku_profit_versions"

    STATUSES = { draft: "draft", published: "published", archived: "archived" }.freeze

    belongs_to :sku, class_name: "Ec::Sku"
    has_many :contexts,
      class_name: "Ec::SkuProfitVersionContext",
      foreign_key: :sku_profit_version_id,
      inverse_of: :profit_version,
      dependent: :destroy

    enum :status, STATUSES, validate: true

    validates :name, :effective_from, presence: true
    validates_associated :contexts
    validate :effective_range_valid
    validate :current_version_not_archived, if: :is_current?
    validate :published_version_has_contexts, if: :published?
    validate :no_overlapping_published_version, if: :published?

    scope :published, -> { where(status: "published") }
    scope :current, -> { where(is_current: true) }
    scope :for_date, ->(date) {
      published.where("effective_from <= ? AND (effective_to IS NULL OR effective_to >= ?)", date, date)
    }

    # The version a SKU is read through: the one marked current, else the published version in
    # effect on `date`, else the newest. `versions` is one SKU's versions, already loaded (so the
    # page and the list queries stay at a fixed number of queries).
    def self.resolve_for(versions, date: Date.current)
      ordered = versions.to_a.sort_by { |version| [ version.effective_from, version.id.to_i ] }.reverse
      date = date.to_date

      ordered.find(&:is_current?) ||
        ordered.find { |version| version.published? && version.effective_from <= date && (version.effective_to.nil? || version.effective_to >= date) } ||
        ordered.first
    end

    # Makes this the SKU's only current version. It is a pointer, not content: the flip does not
    # bump lock_version (that would fail the next save of whoever has the old current version
    # open), so the rows are updated directly and the change is audited by hand.
    def make_current!
      raise ActiveRecord::RecordNotSaved.new("unsaved version", self) if new_record?

      if archived?
        errors.add(:status, :archived)
        raise ActiveRecord::RecordInvalid, self
      end

      transaction do
        siblings = self.class.where(sku_id: sku_id).order(:id).lock.to_a
        siblings.each do |version|
          next unless version.is_current? && version.id != id

          flip_current!(version, false)
        end
        target = siblings.find { |version| version.id == id }
        flip_current!(target, true) unless target.is_current?
        self.is_current = true
        clear_attribute_changes([ "is_current" ])
      end
      self
    end

    def context_for(platform:, market:, delivery_mode:, warehouse_region: nil, company_type: nil)
      normalized_platform = platform.to_s.downcase
      normalized_company_type = company_type.to_s.downcase.presence
      normalized_company_type ||= "general" if normalized_platform == "ozon"
      contexts.find_by(
        platform: normalized_platform,
        market: market.to_s.downcase,
        delivery_mode: delivery_mode.to_s.downcase,
        warehouse_region: warehouse_region.to_s.downcase.presence,
        company_type: normalized_company_type
      )
    end

    def build_copy(effective_from:, name: nil, effective_to: nil)
      copy = dup
      copy.assign_attributes(
        name: name.presence || self.name,
        status: "draft",
        effective_from: effective_from,
        effective_to: effective_to,
        lock_version: 0,
        # A copy is never current: only one version per SKU may be (unique index).
        is_current: false
      )
      contexts.each do |context|
        attributes = context.attributes.slice(
          "platform", "market", "delivery_mode", "warehouse_region", "company_type", "logistics_mode",
          *Ec::SkuProfitVersionContext::INPUT_COLUMNS
        )
        copy.contexts.build(attributes)
      end
      copy
    end

    private

    def flip_current!(version, value)
      version.update_columns(is_current: value)
      version.send(:record_operation_log, "update", { "is_current" => [ !value, value ] })
    end

    def current_version_not_archived
      errors.add(:status, :archived) if archived?
    end

    def effective_range_valid
      return if effective_from.blank? || effective_to.blank? || effective_to >= effective_from

      errors.add(:effective_to, :invalid)
    end

    def published_version_has_contexts
      errors.add(:contexts, :blank) if contexts.empty?
    end

    def no_overlapping_published_version
      return if sku_id.blank? || effective_from.blank?

      relation = self.class.published.where(sku_id: sku_id)
      relation = relation.where.not(id: id) if persisted?
      relation = relation.where("effective_from <= ?", effective_to) if effective_to.present?
      relation = relation.where("effective_to IS NULL OR effective_to >= ?", effective_from)
      errors.add(:effective_from, :taken) if relation.exists?
    end
  end
end
